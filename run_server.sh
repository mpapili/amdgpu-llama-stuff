#! /bin/bash

LLM_DIR="/home/mike/Downloads/LLMs"

# Define the models
declare -A models
models=(
    ["arcee-blitz"]="arcee-ai_Arcee-Blitz-Q6_K.gguf"
    ["mistral_nemo"]="Mistral-Nemo-Instruct-2407-Q6_K_L.gguf"
    ["codestral"]="Codestral-22B-v0.1-Q6_K.gguf"
    ["llama3_8b"]="Meta-Llama-3.1-8B-Instruct-Q6_K.gguf"
    ["deepermes_3_llama_3_8b_q6"]="DeepHermes-3-Llama-3-8B-q6.gguf"
    ["mistral_small_q5"]="Mistral-Small-24B-Instruct-2501-Q5_K_M.gguf"
    ["mistral_small_q6"]="Mistral-Small-24B-Instruct-2501-Q6_K.gguf"
    ["llama3_3_70b"]="Llama-3.3-70B-Instruct-Q4_K_M.gguf"
    ["falcon_3_10b"]="Falcon3-10B-Instruct-q6_k.gguf"
    ["hermes_3_8b"]="Hermes-3-Llama-3.1-8B.Q6_K.gguf"
    ["qwen_2.5_14b_iq4"]="Qwen2.5-14B-Instruct-IQ4_XS.gguf"
    ["qwen_2.5_14b_q6"]="Qwen2.5-14B-Instruct-Q6_K.gguf"
    ["qwen_32b_q5"]="Qwen2.5-32B-Instruct-Q5_K_M.gguf"
    ["qwen_32b_q6"]="Qwen2.5-32B-Instruct-Q6_K.gguf"
    ["qwen_coder_14b_q6"]="Qwen2.5-Coder-14B-Q6_K.gguf"
    ["qwen_coder_32b_iq4"]="Qwen2.5-Coder-32B-IQ4_XS.gguf"
    ["qwen_coder_32b_q5"]="Qwen2.5-Coder-32B-Instruct-Q5_K_M.gguf"
    ["qwen_coder_32b_q6"]="Qwen2.5-Coder-32B-Instruct-Q6_K.gguf"
    ["qwq_iq4"]="Qwen_QwQ-32B-IQ4_XS.gguf"
    ["qwq_q5"]="qwq-32b-q5_k_m.gguf"
    ["qwq_q6"]="Qwen_QwQ-32B-Q6_K.gguf"
    ["phi_4_14b"]="phi-4-IQ4_XS.gguf"
    ["dolphin_r1_mistral_24b-Q6.gguf"]="cognitivecomputations_Dolphin3.0-R1-Mistral-24B-Q6_K_L.gguf"
    ["deepseek_r1_distill_qwen_32b_q5"]="DeepSeek-R1-Distill-Qwen-32B-Q5_K_M.gguf"
    ["deepseek_r1_distill_qwen_32b_q6"]="DeepSeek-R1-Distill-Qwen-32B-Q6_K.gguf"
    ["deepseek_r1_distill_llama_3_8b_q8"]="DeepSeek-R1-Distill-Llama-8B-Q8_0.gguf"
    ["draft_qwen"]="Qwen2.5-1.5B.Q6_K.gguf"
    ["ibm_granite3_2_2b"]="ibm-granite_granite-3.2-2b-instruct-Q5_K_M.gguf"
    ["gemma3_24b_q5"]="google_gemma-3-27b-it-Q5_K_M.gguf"
    ["deephermes_24b_q6"]="DeepHermes-3-Mistral-24B-Preview-q6.gguf"
    ["nemotron_super_49b_iq3"]="nvidia_Llama-3_3-Nemotron-Super-49B-v1-IQ3_M.gguf"
)

# Default context size
DEFAULT_CTX_SIZE=12000

# Default temperature
DEFAULT_TEMP=0.5

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -m|--model)
            MODEL_NAME="$2"
            shift 2
            ;;
        -c|--ctx-size)
            CTX_SIZE="$2"
            shift 2
            ;;
        -t|--temp)
            TEMP="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter passed: $1"
            echo "Usage: $0 --model <model_name> [--ctx-size <context_size>] [--temp <temperature>]"
            echo "Available models:"
            for key in "${!models[@]}"; do
                echo "  $key"
            done
            exit 1
            ;;
    esac
done

# Check if a model name is provided
if [ -z "$MODEL_NAME" ]; then
    echo "Usage: $0 --model <model_name> [--ctx-size <context_size>] [--temp <temperature>]"
    echo "Available models:"
    for key in "${!models[@]}"; do
        echo "  $key"
    done
    exit 1
fi

# Get the model file from the associative array
MODEL_FILE="${models[$MODEL_NAME]}"

# Check if the model file exists
if [ -z "$MODEL_FILE" ]; then
    echo "Model '$MODEL_NAME' not found. Please choose from the following:"
    for key in "${!models[@]}"; do
        echo "  $key"
    done
    exit 1
fi

# Determine if the --chat-template monarch flag should be used
CHAT_TEMPLATE_FLAG=""
if [ "$MODEL_NAME" == "mistral_small" ]; then
    ## CHAT_TEMPLATE_FLAG="--chat-template monarch"
    TEMP=${TEMP:-0.2}  # Set default temperature to 0.2 for mistral_small if not provided
else
    TEMP=${TEMP:-$DEFAULT_TEMP}  # Set default temperature to 0.6 for other models if not provided
fi

# Use default context size if not provided
CTX_SIZE=${CTX_SIZE:-$DEFAULT_CTX_SIZE}

# Run llama-server
sudo HSA_OVERRIDE_GFX_VERSION=10.3.0 ./llama-server \
    -m "${LLM_DIR}/${MODEL_FILE}" \
    --ctx-size "$CTX_SIZE" \
    --mlock \
    -v \
    --gpu-layers 150 \
    --split-mode row \
    --flash-attn \
    --host 0.0.0.0 \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    --temp "$TEMP" \
    --jinja \
    $CHAT_TEMPLATE_FLAG
