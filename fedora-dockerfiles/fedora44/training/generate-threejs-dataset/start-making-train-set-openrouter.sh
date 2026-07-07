#! /bin/bash
#
# OpenRouter variant of start-making-train-set.sh.
#
# Connects to the OpenRouter chat-completions API and uses
# deepseek/deepseek-v4-flash as the generation model.
#
# NOTE: This script posts prompts to a third-party service (OpenRouter).
# Your prompts are sent off-box for generation — be aware of that before
# running sensitive content through it.
#
# The API key is read from the OPENROUTER_API_KEY environment variable.
# Drop your key in there (or fill in the placeholder below) before running:
#
#     export OPENROUTER_API_KEY="sk-or-v1-REPLACE_ME"
#     ./start-making-train-set-openrouter.sh
#
# OpenRouter's endpoint is https://openrouter.ai/api/v1/chat/completions
# and generate_train_set.py appends "/v1/chat/completions" to --base-url,
# so --base-url must be the prefix WITHOUT that trailing path.
#
# OpenRouter has no /tokenize endpoint; generate_train_set.py falls back
# to a char-based token estimate when /tokenize returns an error, so
# token counting still works (just approximately).

# --- placeholder for the API key ---------------------------------------------
# Replace the empty string with your OpenRouter key, OR export
# OPENROUTER_API_KEY in your shell before running. Leaving it blank will
# cause OpenRouter to reject requests with a 401.
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-REPLACE_WITH_YOUR_OPENROUTER_API_KEY}"

echo "max reply length is 4096 still, but total response can be larger"

python3 generate_train_set.py \
	--base-url https://openrouter.ai/api \
	--api-key "${OPENROUTER_API_KEY}" \
	--model deepseek/deepseek-v4-pro \
	--concurrency 1 \
	--max-tokens 18192 \
	--max-reply-tokens 4096 \
	--max-context 18192 \
	--timeout 600 \
	--resume
