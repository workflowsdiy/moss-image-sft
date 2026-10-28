#!/bin/bash
# MOSS-Image-SFT on sd-server, loopback only, every model on the Metal GPU.
# Defaults follow the model card: flow-matching Euler, 50 steps, CFG 3, shift 5, 1024x1024, CPU RNG.
# Per-request overrides (size, seed, steps, negative prompt) come from gen.py.
#   PORT (default 11439)   SKIP_VERIFY=1 to skip the hash check
ROOT=$(cd "$(dirname "$0")" && pwd -P); cd "$ROOT" || exit 1
PORT=${PORT:-11439}
[ -x bin/sd-server ] || { echo "No bin/sd-server: run ./setup.sh."; exit 1; }
[ -f models/selected.env ] || { echo "No models/selected.env: run ./setup.sh."; exit 1; }
source models/selected.env
if [ -z "${SKIP_VERIFY:-}" ]; then
  (cd models && shasum -a 256 -c --quiet SHA256SUMS) || { echo "A model file does not match models/SHA256SUMS."; exit 1; }
fi
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t > /dev/null 2>&1; then
  echo "Port $PORT is already in use ($(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN | awk 'NR==2 {print $1, "pid", $2}'))."; exit 1
fi
mkdir -p logs
export HF_HUB_OFFLINE=1
# pipefail: the script exits with sd-server's status, not tee's.
set -o pipefail
bin/sd-server --listen-ip 127.0.0.1 --listen-port "$PORT" \
  --diffusion-model "models/MOSS-Image-SFT-$MOSS_QUANT.gguf" \
  --llm "models/Qwen3.5-9B-$TE_QUANT.gguf" \
  --vae models/vae/diffusion_pytorch_model.safetensors \
  --tokenizer models/tokenizer/tokenizer.json \
  --cfg-scale 3 --steps 50 --sampling-method euler --scheduler discrete --flow-shift 5 \
  --rng cpu --sampler-rng cpu -W 1024 -H 1024 --diffusion-fa \
  "$@" 2>&1 | tee -a logs/sd-server.log
