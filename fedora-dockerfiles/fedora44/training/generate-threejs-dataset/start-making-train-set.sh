#! /bin/bash

python3 generate_train_set.py --base-url http://127.0.0.1:8080 \
	--concurrency 5 \
	--max-tokens 4096 \
	--max-context 4096 
