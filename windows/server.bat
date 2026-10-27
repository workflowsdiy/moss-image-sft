@echo off
rem Windows counterpart of server.sh: sd-server on 127.0.0.1:%PORT%, every model on the NVIDIA GPU, same sampling defaults.
rem Run it here, or let remote.sh start it for one batch over SSH; it then stops when that SSH session ends.
setlocal
cd /d "%~dp0.." || exit /b 1
if not defined PORT set PORT=11439
if not exist bin\sd-server.exe (echo No bin\sd-server.exe: run windows\setup.bat.& exit /b 1)
if not exist models\selected.env (echo No models\selected.env: run windows\setup.bat.& exit /b 1)
for /f "tokens=1,2 delims==" %%a in (models\selected.env) do set %%a=%%b
if not exist logs mkdir logs
set HF_HUB_OFFLINE=1
bin\sd-server.exe --listen-ip 127.0.0.1 --listen-port %PORT% ^
  --diffusion-model models\MOSS-Image-SFT-%MOSS_QUANT%.gguf --llm models\Qwen3.5-9B-%TE_QUANT%.gguf ^
  --vae models\vae\diffusion_pytorch_model.safetensors --tokenizer models\tokenizer\tokenizer.json ^
  --cfg-scale 3 --steps 50 --sampling-method euler --scheduler discrete --flow-shift 5 ^
  --rng cpu --sampler-rng cpu -W 1024 -H 1024 --diffusion-fa >> logs\sd-server.log 2>&1
