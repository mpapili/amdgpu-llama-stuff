# Generating the training set via OpenRouter

OpenRouter-hosted alternative to `start-making-train-set.sh`, using
`deepseek/deepseek-v4-flash`.

## 1. Get an API key

Grab a key from <https://openrouter.ai/keys> (starts with `sk-or-v1-...`).

## 2. Export it

```bash
export OPENROUTER_API_KEY="REPLACE_ME"
```

(Or paste it directly into the placeholder in
`start-making-train-set-openrouter.sh`.)

## 3. Run

```bash
./start-making-train-set-openrouter.sh
```

It resumes by default — re-run to continue after a stop / crash.

## Notes

- **Prompts are sent off-box** to OpenRouter. Be aware of that before running
  sensitive content.
- **Token counts are approximate**: OpenRouter has no `/tokenize` endpoint, so
  the script falls back to a char-based estimate for both the `--max-context`
  and `--max-reply-tokens` checks.
- **Generation vs. saved-content budgets**: `--max-tokens` is the *generation*
  cap sent to the API (raw output, **including reasoning**). It is set above
  4096 (`8192`) so reasoning models have room to think before answering.
  `--max-reply-tokens` (`4096`) is the binding cap on the **saved** assistant
  reply — i.e. the generation minus any `...` thinking tags. So a reply may
  generate well over 4096 tokens raw, but if the post-thinking content exceeds
  4096 tokens it is rejected and logged to `rejects.jsonl` (reason
  `over_reply_budget`). `--max-context` is a looser full-record
  (prompt + reply) guard.
- **Rate limits**: OpenRouter limits per model/plan. If you see `429`s, drop
  `--concurrency` or raise `--delay` / `--retries` in the script.
- **Debugging empty replies**: if the API keeps returning empty replies, run
  `generate_train_set.py` directly with `--verbose` to dump the raw SSE lines,
  any `error` chunks, reasoning deltas, and `finish_reason` to stderr — this
  is the fastest way to see *why* OpenRouter is returning nothing (mid-stream
  error, reasoning-only output that exhausted the token budget, content
  filter, etc.). The wrapper script doesn't pass `--verbose` by default, so
  either add the flag to the `python3 generate_train_set.py ...` line in
  `start-making-train-set-openrouter.sh` or invoke the script directly:

  ```bash
  python3 generate_train_set.py \
      --base-url https://openrouter.ai/api \
      --api-key "$OPENROUTER_API_KEY" \
      --model deepseek/deepseek-v4-pro \
      --concurrency 1 --max-tokens 8192 --max-reply-tokens 4096 \
      --max-context 8192 --timeout 600 --resume --verbose
  ```

  (Dropping to `--concurrency 1` makes the verbose stream easier to follow.)
