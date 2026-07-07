#!/usr/bin/env python3
"""Shared vision-validation feedback loop for the Three.js dataset tools.

Render generated HTML in headless Chromium (Playwright), screenshot it, and
ask a vision-capable llama.cpp endpoint whether it looks acceptable for the
original prompt. If broken, the model returns fixed HTML; we re-render and
re-validate recursively until it accepts or max_depth is hit.

Both viewer.py (per-row, interactive) and generate_train_set.py (per-prompt,
batch) import this so they run the *same* feedback loop and the *same*
token-budget gate — no drift between the two.

Standard library only (Playwright is imported lazily inside screenshot_html,
so importing this module never requires it).
"""
import base64
import json
import traceback
import urllib.error
import urllib.request


class VisionConfig:
    """All knobs the vision loop needs, bundled so the viewer (env-driven)
    and the generator (argparse-driven) build it identically."""

    def __init__(self, base_url, model="local-model", api_key="",
                 timeout=600, max_tokens=8192, max_depth=5,
                 max_reply_tokens=4096, max_context=4096):
        self.base_url = (base_url or "").rstrip("/")
        self.model = model
        self.api_key = api_key
        self.timeout = timeout
        self.max_tokens = max_tokens
        self.max_depth = max_depth
        self.max_reply_tokens = max_reply_tokens
        self.max_context = max_context
        # Mutable holder so count_tokens can flip to the char-estimate path
        # after the first /tokenize failure (benign race across threads).
        self.tokenizer_ok = {"value": True}


def extract_html(content):
    """Pull the first ```html ... ``` fenced block out of `content`."""
    start = content.find("```html")
    if start == -1:
        start = content.find("```")
        if start == -1:
            return ""
        start += 3
    else:
        start += len("```html")
    end = content.find("```", start)
    if end == -1:
        return content[start:].strip()
    return content[start:end].strip()


def derive_subject(prompt):
    """Pull a short noun phrase out of the original prompt to fill the
    'acceptable _____' blank — e.g. 'Three.js scene featuring a cat'."""
    p = (prompt or "").strip()
    low = p.lower()
    for kw in ("featuring", "displaying", "showing", "depicting", "rendering"):
        if kw in low:
            i = low.index(kw) + len(kw)
            rest = p[i:].strip().rstrip(".").strip()
            if rest:
                tail = rest[0].lower() + rest[1:]
                return f"Three.js scene {kw} {tail}"
    if "three.js" in low:
        return "Three.js scene"
    return p or "the requested page"


def format_error(e, include_tb=True):
    """Stringify an exception with as much detail as possible. For HTTP
    errors this includes the status and the response body (where llama.cpp
    puts the real reason, e.g. 'model not loaded' / 'image input not
    supported')."""
    if include_tb:
        parts = [traceback.format_exc().rstrip()]
    else:
        parts = [f"{type(e).__name__}: {e}"]
    if isinstance(e, urllib.error.HTTPError):
        body = ""
        try:
            raw = e.read()
            body = raw.decode("utf-8", "replace").strip() if raw else ""
        except Exception as br:
            body = f"(could not read body: {br})"
        parts.append(f"HTTP {e.code} {e.reason}")
        if body:
            parts.append("response body:\n" + body[:4000])
    elif isinstance(e, urllib.error.URLError):
        parts.append(f"URL error reason: {e.reason}")
    return "\n".join(parts)


def screenshot_html(html, timeout_ms=20000):
    """Render `html` in headless Chromium via Playwright; return PNG bytes.

    Waits for network idle (CDN-loaded Three.js) and for a <canvas> to exist
    before painting a frame. SwiftShader flags give WebGL under headless
    software rendering; --no-sandbox lets Chromium run as root in a container.
    """
    from playwright.sync_api import sync_playwright

    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            headless=True,
            args=[
                "--use-gl=angle",
                "--use-angle=swiftshader",
                "--enable-unsafe-swiftshader",
                "--no-sandbox",
                "--disable-dev-shm-usage",
            ],
        )
        context = browser.new_context(
            viewport={"width": 1280, "height": 800}, device_scale_factor=1
        )
        page = context.new_page()
        try:
            page.set_content(html, wait_until="networkidle", timeout=timeout_ms)
            try:
                page.wait_for_function(
                    "() => { const c = document.querySelector('canvas'); "
                    "return c && c.width > 0 && c.height > 0; }",
                    timeout=timeout_ms,
                )
            except Exception:
                pass  # not all pages use a canvas; screenshot anyway
            page.wait_for_timeout(800)
            return page.screenshot(full_page=False)
        finally:
            context.close()
            browser.close()


def ask_vision_llm(cfg, prompt, subject, png_bytes):
    """POST the screenshot + the accept/fix instruction to the llama.cpp
    chat-completions endpoint in OpenAI vision format. Returns the model's
    text reply (which may contain a ```html fix block)."""
    data_url = "data:image/png;base64," + base64.b64encode(png_bytes).decode("ascii")
    instruction = (
        "You are reviewing a rendered screenshot of a single-file HTML page "
        "that was generated to satisfy this request:\n\n"
        f'"{prompt}"\n\n'
        f"Does this look like an acceptable {subject}, or is it broken "
        "(blank page, crashed, missing the requested object, JS errors, "
        "wrong scene)?\n"
        "- If it is ACCEPTABLE, reply with exactly the word: ACCEPTABLE\n"
        "- If it is BROKEN, reply with the complete FIXED single-file HTML "
        "for the same request, wrapped in a ```html fenced block. Include "
        "the full <!DOCTYPE html> document.\n"
    )
    payload = {
        "model": cfg.model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": instruction},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            }
        ],
        "max_tokens": cfg.max_tokens,
        "temperature": 0.2,
        "stream": False,
    }
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if cfg.api_key:
        headers["Authorization"] = "Bearer " + cfg.api_key
    data = json.dumps(payload).encode("utf-8")
    url = cfg.base_url + "/v1/chat/completions"
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=cfg.timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", "replace").strip()
        except Exception:
            pass
        raise RuntimeError(
            f"LLM request to {url} failed: HTTP {e.code} {e.reason}"
            + (f"\nresponse body:\n{body[:4000]}" if body else "")
        ) from e
    except urllib.error.URLError as e:
        raise RuntimeError(
            f"LLM request to {url} failed (connection): {e.reason}. "
            f"Is the llama.cpp server reachable at {cfg.base_url}?"
        ) from e

    try:
        obj = json.loads(raw)
    except json.JSONDecodeError as e:
        raise RuntimeError(
            f"LLM returned non-JSON response ({len(raw)} bytes): {raw[:1000]}"
        ) from e

    if obj.get("error") and not obj.get("choices"):
        err = obj["error"]
        msg = err.get("message") if isinstance(err, dict) else str(err)
        raise RuntimeError(f"LLM endpoint returned an error: {msg}")

    choices = obj.get("choices") or []
    if not choices:
        raise RuntimeError(
            "LLM returned no choices. Full response:\n"
            + json.dumps(obj, ensure_ascii=False)[:4000]
        )
    return (choices[0].get("message", {}) or {}).get("content", "") or ""


def count_tokens(cfg, text):
    """Token count via the llama.cpp /tokenize endpoint, falling back to the
    same conservative (len+2)//3 char estimate generate_train_set.py uses when
    /tokenize is unavailable. Returns (n_tokens, used_real_tokenizer)."""
    if cfg.tokenizer_ok["value"]:
        url = cfg.base_url + "/tokenize"
        payload = json.dumps({"content": text}).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        if cfg.api_key:
            headers["Authorization"] = "Bearer " + cfg.api_key
        req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=cfg.timeout) as resp:
                obj = json.loads(resp.read().decode("utf-8"))
            toks = obj.get("tokens")
            if isinstance(toks, list):
                return len(toks), True
        except Exception:
            cfg.tokenizer_ok["value"] = False
    return (len(text) + 2) // 3, False


def check_row_budget(cfg, prompt, reply):
    """Verify the would-be-saved reply fits both the reply budget and the
    full-record (prompt+reply) context budget — the same gate
    generate_train_set.py applies on generation. Returns a dict."""
    rt, used_rt = count_tokens(cfg, reply)
    if rt > cfg.max_reply_tokens:
        return {"ok": False, "reason": "over_reply_budget",
                "reply_tokens": rt, "total_tokens": None,
                "method": "tokenizer" if used_rt else "estimate",
                "limit_reply": cfg.max_reply_tokens,
                "limit_context": cfg.max_context}
    total, used_tot = count_tokens(cfg, prompt + "\n" + reply)
    if total > cfg.max_context:
        return {"ok": False, "reason": "over_context_budget",
                "reply_tokens": rt, "total_tokens": total,
                "method": "tokenizer" if (used_rt or used_tot) else "estimate",
                "limit_reply": cfg.max_reply_tokens,
                "limit_context": cfg.max_context}
    return {"ok": True, "reason": None,
            "reply_tokens": rt, "total_tokens": total,
            "method": "tokenizer" if (used_rt or used_tot) else "estimate",
            "limit_reply": cfg.max_reply_tokens,
            "limit_context": cfg.max_context}


def replace_html_in_content(content, new_html):
    """Return `content` with its first ```html ... ``` fenced block's body
    replaced by new_html, preserving any surrounding prose. If there is no
    fence, wrap new_html in one (the original content was bare HTML)."""
    open_tag = "```html"
    start = content.find(open_tag)
    if start == -1:
        bare = content.find("```")
        if bare == -1:
            return f"```html\n{new_html}\n```"
        start = bare
        open_tag = "```"
    body_start = start + len(open_tag)
    end = content.find("```", body_start)
    if end == -1:
        return content[:start] + f"```html\n{new_html}\n```"
    after = end + 3
    return content[:start] + f"```html\n{new_html}\n```" + content[after:]


def validate_row(cfg, html, prompt, log):
    """Screenshot -> LLM -> fix -> re-validate, recursively, until the model
    accepts or cfg.max_depth is hit. `log(msg)` reports progress. Returns
    (final_html, ok) where ok means the model explicitly accepted.

    On screenshot/LLM failure the loop bails with ok=False and the current
    (unchanged) html, so callers can fall back to the original reply rather
    than dropping the row entirely.
    """
    subject = derive_subject(prompt)
    log(f"Subject for judgement: {subject}")
    current = html
    for depth in range(1, cfg.max_depth + 1):
        log(f"[round {depth}] rendering + screenshotting HTML "
            f"({len(current)} chars)…")
        try:
            png = screenshot_html(current)
        except Exception as e:
            log(f"[round {depth}] screenshot FAILED:\n" + format_error(e))
            if "No module named 'playwright'" in str(e):
                log("Playwright is not installed in this environment. Run via "
                    "the podman runner so it executes in the container that "
                    "has Chromium.")
            return current, False
        log(f"[round {depth}] screenshot OK ({len(png)} bytes); asking LLM…")
        try:
            reply = ask_vision_llm(cfg, prompt, subject, png)
        except Exception as e:
            log(f"[round {depth}] LLM call FAILED:\n" + format_error(e))
            return current, False

        fixed = extract_html(reply)
        if fixed:
            log(f"[round {depth}] LLM says BROKEN, returned fixed HTML "
                f"({len(fixed)} chars); re-validating…")
            current = fixed
            continue
        if "acceptable" in reply.lower():
            log(f"[round {depth}] LLM says ACCEPTABLE.")
            return current, True
        log(f"[round {depth}] LLM gave no fix and didn't accept: "
            f"{reply.strip()[:160]}")
        return current, False

    log(f"Hit max depth ({cfg.max_depth}) without an explicit accept; "
        f"keeping the original HTML.")
    return current, False
