#!/usr/bin/env python3
"""
Generate a synthetic train.jsonl dataset by querying an OpenAI-compatible
endpoint (e.g. llama-server from llama.cpp) with prompts from a text file.

Runs multiple requests concurrently (default 5) via a thread pool — plain
standard library, no async HTTP deps. Uses STREAMING (SSE) like the web UI
for robustness on long generations.

Each finished example is validated against a token budget (default 4096),
counted with the server's own /tokenize endpoint (falls back to a
conservative char estimate).

Standard library only — no pip installs required.
"""

import argparse
import json
import os
import re
import sys
import time
import threading
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed


# Matches a complete `...` block (closed) or a dangling open tag to the
# end of the string (the model ran out of tokens mid-think). DOTALL so a
# block can span newlines.
_THINK_TAG_RE = re.compile(r"<think>.*?</think>|<think>.*", re.DOTALL)


def strip_think_tags(text):
    """Remove `...` reasoning blocks (and any dangling open tag) from a
    model reply before it is written to the dataset."""
    return _THINK_TAG_RE.sub("", text).strip()


# ---- Shared state guarded by a lock (threads write to the same files) ----
_write_lock = threading.Lock()
_stats_lock = threading.Lock()
_stats = {"succeeded": 0, "skipped": 0, "failed": 0, "rejected": 0}
_tokenizer_ok = {"value": True}  # mutable holder so threads can flip it off


def read_prompts(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def load_done_prompts(out_path):
    done = set()
    if not os.path.exists(out_path):
        return done
    with open(out_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                for msg in obj.get("messages", []):
                    if msg.get("role") == "user":
                        done.add(msg.get("content"))
            except json.JSONDecodeError:
                pass
    return done


def _post_json(url, payload, api_key, timeout):
    data = json.dumps(payload).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Connection": "keep-alive",
        "Accept-Encoding": "identity",
    }
    if api_key:
        headers["Authorization"] = "Bearer " + api_key
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def count_tokens(base_url, api_key, text, timeout):
    """Count tokens via /tokenize; fall back to a char estimate. Thread-safe:
    reads/writes the shared _tokenizer_ok flag under no lock (a benign race —
    worst case a couple of extra failed attempts before it settles False)."""
    if _tokenizer_ok["value"]:
        url = base_url.rstrip("/") + "/tokenize"
        try:
            obj = _post_json(url, {"content": text}, api_key, timeout)
            tokens = obj.get("tokens")
            if isinstance(tokens, list):
                return len(tokens), True
        except (urllib.error.URLError, urllib.error.HTTPError,
                ConnectionError, OSError, TimeoutError,
                json.JSONDecodeError, KeyError):
            _tokenizer_ok["value"] = False

    estimate = (len(text) + 2) // 3
    return estimate, False


def query_endpoint(base_url, api_key, model, system_prompt, user_prompt,
                   temperature, max_tokens, timeout, verbose=False):
    """Streaming chat-completion; assemble text from SSE deltas.

    With verbose=True, dumps every raw SSE line, any reasoning deltas, and
    the final finish_reason to stderr — useful for diagnosing empty replies
    (mid-stream errors, reasoning-only output, content filters, etc.)."""
    url = base_url.rstrip("/") + "/v1/chat/completions"

    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": user_prompt})

    payload = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "stream": True,
    }

    data = json.dumps(payload).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
        "Connection": "keep-alive",
        "Accept-Encoding": "identity",
    }
    if api_key:
        headers["Authorization"] = "Bearer " + api_key

    req = urllib.request.Request(url, data=data, headers=headers, method="POST")

    pieces = []
    finish_reason = None
    if verbose:
        print(f"[verbose] POST {url}\n[verbose] model={model} "
              f"max_tokens={max_tokens} temperature={temperature}",
              file=sys.stderr)
        print(f"[verbose] user_prompt={user_prompt[:120]!r}", file=sys.stderr)

    with urllib.request.urlopen(req, timeout=timeout) as resp:
        for raw_line in resp:
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            if verbose:
                print(f"[verbose] << {line}", file=sys.stderr)
            if not line.startswith("data:"):
                continue
            chunk = line[len("data:"):].strip()
            if chunk == "[DONE]":
                break
            try:
                obj = json.loads(chunk)
            except json.JSONDecodeError:
                continue
            # OpenRouter streams mid-stream errors as {"error": {...}} with
            # no "choices" key. The old code skipped these silently, which is
            # the usual cause of mysterious "empty replies" — surface the
            # message instead so the retry log shows the real reason.
            if "error" in obj and not obj.get("choices"):
                err = obj["error"]
                msg = err.get("message") if isinstance(err, dict) else str(err)
                print(f"[verbose] stream error: {msg}", file=sys.stderr)
                return ""
            choices = obj.get("choices")
            if not choices:
                continue
            delta = choices[0].get("delta", {})
            content = delta.get("content")
            if content:
                pieces.append(content)
            # Reasoning models (e.g. DeepSeek) stream chain-of-thought under
            # "reasoning" / "reasoning_content", NOT "content". Show it under
            # --verbose so reasoning-only replies are obvious.
            if verbose:
                reasoning = delta.get("reasoning") or delta.get("reasoning_content")
                if reasoning:
                    print(f"[verbose] (reasoning) {reasoning[:160]!r}",
                          file=sys.stderr)
            fr = choices[0].get("finish_reason")
            if fr:
                finish_reason = fr

    assembled = "".join(pieces).strip()
    if verbose:
        print(f"[verbose] finish_reason={finish_reason!r} "
              f"content_len={len(assembled)}", file=sys.stderr)
    return assembled


def append_example(out_path, user_prompt, assistant_reply):
    record = {
        "messages": [
            {"role": "user", "content": user_prompt},
            {"role": "assistant", "content": assistant_reply},
        ]
    }
    line = json.dumps(record, ensure_ascii=False)
    # Guard the shared output file so concurrent writes don't interleave.
    with _write_lock:
        with open(out_path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
            f.flush()


def append_reject(rejects_path, user_prompt, assistant_reply, n_tokens, limit,
                  reason="over_token_budget"):
    rec = {
        "reason": reason,
        "tokens": n_tokens,
        "limit": limit,
        "messages": [
            {"role": "user", "content": user_prompt},
            {"role": "assistant", "content": assistant_reply},
        ],
    }
    with _write_lock:
        with open(rejects_path, "a", encoding="utf-8") as rf:
            rf.write(json.dumps(rec, ensure_ascii=False) + "\n")
            rf.flush()


def token_text_for_record(user_prompt, assistant_reply):
    return user_prompt + "\n" + assistant_reply


def bump(key, n=1):
    with _stats_lock:
        _stats[key] += n


def process_prompt(idx, total, prompt, args):
    """Worker: run one prompt end-to-end (generate -> validate -> write).
    Returns a short status string for logging. Runs in a worker thread."""
    tag = f"[{idx}/{total}]"

    reply = None
    for attempt in range(1, args.retries + 1):
        try:
            reply = query_endpoint(
                args.base_url, args.api_key, args.model,
                args.system, prompt,
                args.temperature, args.max_tokens, args.timeout,
                verbose=args.verbose,
            )
            if reply:
                break
            print(f"{tag} Empty reply on attempt {attempt}, retrying...",
                  file=sys.stderr)
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            print(f"{tag} HTTP {e.code} attempt {attempt}: {body[:200]}",
                  file=sys.stderr)
        except (urllib.error.URLError, ConnectionError, OSError, TimeoutError) as e:
            print(f"{tag} Connection error attempt {attempt}: {e}", file=sys.stderr)
        except (KeyError, IndexError, json.JSONDecodeError) as e:
            print(f"{tag} Bad response attempt {attempt}: {e}", file=sys.stderr)

        if attempt < args.retries:
            time.sleep(2 ** (attempt - 1))

    if not reply:
        bump("failed")
        return f"{tag} FAILED: {prompt[:50]!r}"

    reply = strip_think_tags(reply)

    # Saved-reply budget: the assistant content AFTER stripping <think> tags
    # must fit --max-reply-tokens. Generation itself may run longer than this
    # (--max-tokens controls the API cap and can exceed 4096 to leave room for
    # reasoning); this cap is what bounds the final, saved content.
    reply_tokens, used_tokenizer = count_tokens(
        args.base_url, args.api_key, reply, args.timeout
    )
    if reply_tokens > args.max_reply_tokens:
        append_reject(args.rejects, prompt, reply, reply_tokens,
                      args.max_reply_tokens, reason="over_reply_budget")
        bump("rejected")
        return (f"{tag} REJECT reply ({reply_tokens} > "
                f"{args.max_reply_tokens} tok): {prompt[:50]!r}")

    # Full-record budget: prompt + reply together must fit --max-context
    # (the training context window).
    text = token_text_for_record(prompt, reply)
    n_tokens, _ = count_tokens(args.base_url, args.api_key, text, args.timeout)
    if n_tokens > args.max_context:
        append_reject(args.rejects, prompt, reply, n_tokens,
                      args.max_context, reason="over_context_budget")
        bump("rejected")
        return f"{tag} REJECT ctx ({n_tokens} > {args.max_context} tok): {prompt[:50]!r}"

    append_example(args.out, prompt, reply)
    bump("succeeded")
    method = "tokenizer" if used_tokenizer else "estimate"
    return (f"{tag} OK (reply {reply_tokens} tok, total {n_tokens} tok, "
            f"{method}): {prompt[:45]!r} -> {reply[:45]!r}")


def main():
    parser = argparse.ArgumentParser(
        description="Build train.jsonl from an OpenAI-compatible endpoint, "
                    "concurrently, with per-record token-budget validation."
    )
    parser.add_argument("--prompts", default="prompts.txt")
    parser.add_argument("--out", default="train.jsonl")
    parser.add_argument("--base-url", default="http://127.0.0.1:8080",
                        help="Use 127.0.0.1 (not 'localhost') to avoid IPv6 resets.")
    parser.add_argument("--model", default="local-model")
    parser.add_argument("--api-key", default=os.environ.get("OPENAI_API_KEY", ""))
    parser.add_argument("--system", default="")
    parser.add_argument("--temperature", type=float, default=0.8)
    parser.add_argument("--max-tokens", type=int, default=1024,
                        help="API generation cap (raw output incl. reasoning). "
                             "May exceed --max-reply-tokens to give reasoning "
                             "models room to think before producing the answer.")
    parser.add_argument("--max-context", type=int, default=4096,
                        help="Max tokens for the full record (prompt + reply).")
    parser.add_argument("--max-reply-tokens", type=int, default=4096,
                        help="Max tokens allowed in the SAVED assistant reply "
                             "(after stripping <think> tags). The binding cap "
                             "on the final saved content.")
    parser.add_argument("--timeout", type=float, default=600.0)
    parser.add_argument("--delay", type=float, default=0.0,
                        help="Ignored in concurrent mode (kept for compatibility).")
    parser.add_argument("--retries", type=int, default=5)
    parser.add_argument("--concurrency", type=int, default=5,
                        help="Number of requests to run in parallel.")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--verbose", action="store_true",
                        help="Dump raw SSE lines, reasoning deltas, stream "
                             "errors, and finish_reason to stderr. Use this "
                             "to diagnose empty replies from the API.")
    parser.add_argument("--rejects", default="rejects.jsonl")
    args = parser.parse_args()

    if not os.path.exists(args.prompts):
        sys.exit(f"Prompts file not found: {args.prompts}")

    prompts = read_prompts(args.prompts)
    if not prompts:
        sys.exit("No prompts found (file is empty or all blank lines).")

    done = load_done_prompts(args.out) if args.resume else set()

    # Build the work list up front, honoring --resume, keeping original indices.
    work = []
    total = len(prompts)
    for i, prompt in enumerate(prompts, start=1):
        if args.resume and prompt in done:
            bump("skipped")
            print(f"[{i}/{total}] SKIP (already done): {prompt[:60]!r}")
            continue
        work.append((i, prompt))

    print(f"Dispatching {len(work)} prompts with concurrency={args.concurrency}...\n")

    # Run the pool. Each future is one prompt processed end-to-end.
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = {
            pool.submit(process_prompt, i, total, prompt, args): i
            for (i, prompt) in work
        }
        for fut in as_completed(futures):
            try:
                print(fut.result())
            except Exception as e:  # a worker blew up unexpectedly
                idx = futures[fut]
                bump("failed")
                print(f"[{idx}/{total}] WORKER ERROR: {e}", file=sys.stderr)

    s = _stats
    print(f"\nDone. {s['succeeded']} written, {s['skipped']} skipped, "
          f"{s['rejected']} rejected (over budget), {s['failed']} failed.")
    print(f"Output: {args.out}")
    if s["rejected"]:
        print(f"Over-budget examples logged to: {args.rejects}")
    if not _tokenizer_ok["value"]:
        print("NOTE: /tokenize endpoint was unavailable — token counts are "
              "conservative CHARACTER-BASED ESTIMATES.", file=sys.stderr)


if __name__ == "__main__":
    main()
