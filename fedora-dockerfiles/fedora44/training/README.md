# how to train

```bash
./run-trainer.sh
```

from within the container:

```bash
python gemma4-workspace/train.py
```

should output an 'adapter-final/' directory

```bash
# save as gguf
cd llama-cpp/
python convert_lora_to_gguf.py \
  ../adapter-final/ \
  --base /models/gemma4-12b \
  --outfile /workspace/adapter-final/gemma4-12b-f16-test-adapter.gguf \
  --outtype f16
```
