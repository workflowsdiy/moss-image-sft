@echo off
rem Windows/CUDA counterpart of setup.sh. Run once while online; re-running skips what is there.
rem Builds bin\sd-server.exe with Visual Studio 2022's CMake and Ninja and the CUDA toolkit, then downloads the same
rem GGUF set into models\. Needs git, uv, Visual Studio 2022 (C++ workload) and CUDA 12 with its VS integration.
rem   SDCPP_REF / MOSS_QUANT / TE_QUANT as in setup.sh; CUDA_ARCH (default native: the GPU in this machine)
setlocal
cd /d "%~dp0.." || exit /b 1
if not defined SDCPP_DIR set SDCPP_DIR=%USERPROFILE%\dev\stable-diffusion.cpp
if not defined SDCPP_REF set SDCPP_REF=b13a482
if not defined MOSS_QUANT set MOSS_QUANT=Q8_0
if not defined TE_QUANT set TE_QUANT=Q8_0
if not defined CUDA_ARCH set CUDA_ARCH=native
set HF=uvx --from huggingface_hub[hf_xet]==2.3.0 hf
rem Hugging Face commits the downloads are pinned to, so a file replaced upstream is never fetched silently.
set MOSS_REV=a013f7442e672e67b21f485b4b4f369df5500847
set TE_REV=3885219b6810b007914f3a7950a8d1b469d598a5
set VAE_REV=8fb0d8c3a126cfd1406acaf96698dbfe9d99b680

if exist bin\sd-server.exe goto models
set VS=
for /f "usebackq delims=" %%v in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VS=%%v
if not defined VS (echo Visual Studio 2022 with the C++ workload was not found.& exit /b 1)
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
if not exist "%SDCPP_DIR%" git clone --recursive https://github.com/leejet/stable-diffusion.cpp "%SDCPP_DIR%" || exit /b 1
git -C "%SDCPP_DIR%" fetch --tags origin || exit /b 1
git -C "%SDCPP_DIR%" checkout %SDCPP_REF% || exit /b 1
git -C "%SDCPP_DIR%" submodule update --init --recursive || exit /b 1
cmake -S "%SDCPP_DIR%" -B "%SDCPP_DIR%\build" -G Ninja -DSD_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=%CUDA_ARCH% -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release || exit /b 1
cmake --build "%SDCPP_DIR%\build" --target sd-server sd-cli || exit /b 1
if not exist bin mkdir bin
copy /y "%SDCPP_DIR%\build\bin\sd-server.exe" bin\ >nul || exit /b 1
copy /y "%SDCPP_DIR%\build\bin\sd-cli.exe" bin\ >nul || exit /b 1
for /f %%h in ('git -C "%SDCPP_DIR%" rev-parse --short HEAD') do echo %SDCPP_REF% %%h> bin\SDCPP_VERSION

:models
%HF% download unsloth/MOSS-Image-SFT-GGUF MOSS-Image-SFT-%MOSS_QUANT%.gguf --revision %MOSS_REV% --local-dir models || exit /b 1
%HF% download unsloth/Qwen3.5-9B-GGUF Qwen3.5-9B-%TE_QUANT%.gguf --revision %TE_REV% --local-dir models || exit /b 1
%HF% download unsloth/MOSS-Image-SFT-FP8 vae/diffusion_pytorch_model.safetensors tokenizer/tokenizer.json --revision %VAE_REV% --local-dir models || exit /b 1
(echo MOSS_QUANT=%MOSS_QUANT%& echo TE_QUANT=%TE_QUANT%)> models\selected.env
echo Ready. Start the server with windows\server.bat, or from another machine use remote.sh.
