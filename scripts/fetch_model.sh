#!/bin/bash
# Puts the Qwen3-ASR 0.6B MLX 5-bit weights in Models/ so the build can bundle them.
# Reuses speech-swift's local cache when present; otherwise downloads from Hugging Face.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME=Qwen3-ASR-0.6B-MLX-5bit
REPO=aufklarer/$NAME
DEST=Models/$NAME
FILES=(config.json model.safetensors vocab.json merges.txt tokenizer_config.json)

have_all() { for f in "${FILES[@]}"; do [ -s "$DEST/$f" ] || return 1; done; }
if have_all; then echo "Model already in $DEST"; exit 0; fi

mkdir -p "$DEST"
CACHE="$HOME/Library/Caches/qwen3-speech/models/aufklarer/$NAME"
if [ -s "$CACHE/model.safetensors" ]; then
  echo "Copying from $CACHE"
  for f in "${FILES[@]}"; do cp "$CACHE/$f" "$DEST/$f"; done
else
  echo "Downloading $REPO"
  for f in "${FILES[@]}"; do
    curl -fL --retry 3 -o "$DEST/$f" "https://huggingface.co/$REPO/resolve/main/$f"
  done
fi
chmod 644 "$DEST"/*
have_all && echo "Model ready in $DEST ($(du -sh "$DEST" | cut -f1))"
