#! /bin/bash

python3 generate_train_set.py --base-url http://192.168.1.1:8080 \
	--concurrency 1 \
	--max-tokens 4096 \
	--max-context 4096 \
	--resume
