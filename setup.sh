#!/bin/bash
# Build bin/sd-server (stable-diffusion.cpp, Metal) and download the MOSS-Image-SFT GGUF set into models/.
# Run once while online. Re-running skips what is already there.
#   SDCPP_REF   stable-diffusion.cpp commit/tag to build (default: b13a482, a commit with MOSS-Image support)
#   MOSS_QUANT  transformer quant from unsloth/MOSS-Image-SFT-GGUF (default: Q8_0; UD-Q4_K_XL for less memory)
#   TE_QUANT    Qwen3.5-9B text encoder quant from unsloth/Qwen3.5-9B-GGUF (default: Q8_0)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd -P); cd "$ROOT"
SDCPP_DIR=${SDCPP_DIR:-$HOME/dev/stable-diffusion.cpp}
SDCPP_REF=${SDCPP_REF:-b13a482}
MOSS_QUANT=${MOSS_QUANT:-Q8_0}
TE_QUANT=${TE_QUANT:-Q8_0}
HF=(uvx --from 'huggingface_hub[hf_xet]' hf)
# Hugging Face commits the downloads are pinned to, so a file replaced upstream is never fetched silently.
MOSS_REV=a013f7442e672e67b21f485b4b4f369df5500847 TE_REV=3885219b6810b007914f3a7950a8d1b469d598a5
VAE_REV=8fb0d8c3a126cfd1406acaf96698dbfe9d99b680

# 1. sd-server: Metal, static, release.
if [ ! -x bin/sd-server ]; then
  [ -d "$SDCPP_DIR" ] || git clone --recursive https://github.com/leejet/stable-diffusion.cpp "$SDCPP_DIR"
  git -C "$SDCPP_DIR" fetch --tags origin
  git -C "$SDCPP_DIR" checkout "$SDCPP_REF"
  git -C "$SDCPP_DIR" submodule update --init --recursive
  uvx cmake -S "$SDCPP_DIR" -B "$SDCPP_DIR/build" -DSD_METAL=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release
  uvx cmake --build "$SDCPP_DIR/build" --target sd-server sd-cli -j 6
  mkdir -p bin
  cp "$SDCPP_DIR/build/bin/sd-server" "$SDCPP_DIR/build/bin/sd-cli" bin/
  echo "$SDCPP_REF $(git -C "$SDCPP_DIR" rev-parse --short HEAD)" > bin/SDCPP_VERSION
fi

# 2. Models: quantized transformer, Qwen3.5-9B text encoder, and the unchanged VAE + MOSS tokenizer.
#    The tokenizer must be MOSS's own: its vocabulary differs from the one embedded in stock Qwen GGUFs.
"${HF[@]}" download unsloth/MOSS-Image-SFT-GGUF "MOSS-Image-SFT-$MOSS_QUANT.gguf" --revision "$MOSS_REV" --local-dir models
"${HF[@]}" download unsloth/Qwen3.5-9B-GGUF "Qwen3.5-9B-$TE_QUANT.gguf" --revision "$TE_REV" --local-dir models
"${HF[@]}" download unsloth/MOSS-Image-SFT-FP8 vae/diffusion_pytorch_model.safetensors tokenizer/tokenizer.json \
  --revision "$VAE_REV" --local-dir models

# 3. Pin what was downloaded, so server.sh can refuse a changed file.
(cd models && shasum -a 256 "MOSS-Image-SFT-$MOSS_QUANT.gguf" "Qwen3.5-9B-$TE_QUANT.gguf" \
  vae/diffusion_pytorch_model.safetensors tokenizer/tokenizer.json > SHA256SUMS)
printf 'MOSS_QUANT=%s\nTE_QUANT=%s\n' "$MOSS_QUANT" "$TE_QUANT" > models/selected.env
echo "Ready. Start the server with ./server.sh, then ./gen.py \"a neon sign that says HELLO\""
