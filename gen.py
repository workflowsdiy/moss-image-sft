#!/usr/bin/env python3
"""Generate an image from the running sd-server (OpenAI-style /v1/images/generations). Standard library only.

  ./gen.py "a storefront sign that says OPEN 24/7"
  ./gen.py --prompt-file examples/fridge_note.txt -o outputs/fridge.png
  ./gen.py --layout examples/layout.json            # JSON layout prompt (size must match the layout's canvas)
  ./gen.py "..." --size 1456x1024 --seed 7 --steps 30 --negative "blurry"
"""
import argparse, base64, json, os, sys, time, urllib.request
from datetime import datetime
from pathlib import Path

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("prompt", nargs="?")
ap.add_argument("--prompt-file", type=Path)
ap.add_argument("--layout", type=Path, help="layout JSON (summary/items, yxyx, abs_centralized)")
ap.add_argument("--size", default="1024x1024", help="WxH, each a multiple of 16")
ap.add_argument("--seed", type=int, default=42)
ap.add_argument("--steps", type=int, help="default: the server's (50)")
ap.add_argument("--negative", help="negative prompt (default: empty)")
ap.add_argument("--extra", help="more sd.cpp request fields as JSON, merged into sd_cpp_extra_args")
ap.add_argument("--server", default=f"http://127.0.0.1:{os.environ.get('PORT', '11439')}")
ap.add_argument("-o", "--out", type=Path)
a = ap.parse_args()

if a.layout:
    prompt = json.dumps(json.loads(a.layout.read_text(encoding="utf-8")), ensure_ascii=False)
elif a.prompt_file:
    prompt = a.prompt_file.read_text(encoding="utf-8").strip()
else:
    prompt = a.prompt
if not prompt:
    ap.error("give a prompt, --prompt-file or --layout")
if "<sd_cpp_extra_args>" in prompt:
    ap.error("the prompt contains <sd_cpp_extra_args>; use --seed, --steps, --negative or --extra instead")
w, h = (int(v) for v in a.size.lower().split("x"))
if w % 16 or h % 16:
    ap.error("width and height must be multiples of 16")

extra = {"seed": a.seed}
if a.steps:
    extra["sample_params"] = {"sample_steps": a.steps}
if a.negative:
    extra["negative_prompt"] = a.negative
if a.extra:
    extra.update(json.loads(a.extra))

body = {
    "model": "moss-image-sft",
    "prompt": f"{prompt}<sd_cpp_extra_args>{json.dumps(extra)}</sd_cpp_extra_args>",
    "size": f"{w}x{h}",
    "n": 1,
    "output_format": "png",
}
req = urllib.request.Request(f"{a.server}/v1/images/generations", json.dumps(body).encode(),
                             {"Content-Type": "application/json"})
t0 = time.time()
try:
    with urllib.request.urlopen(req, timeout=1800) as r:
        data = json.load(r)
except urllib.error.URLError as e:
    sys.exit(f"sd-server not reachable at {a.server} ({e}). Start it with ./server.sh")

item = data["data"][0]
b64 = item.get("b64_json") or item.get("url", "").split(",", 1)[-1]
out = a.out or Path("outputs") / f"moss_{datetime.now():%Y%m%d_%H%M%S}_s{a.seed}.png"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_bytes(base64.b64decode(b64))
print(f"{out}  ({w}x{h}, seed {a.seed}, {time.time() - t0:.0f}s)")
