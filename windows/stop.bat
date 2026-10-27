@echo off
rem Stops this checkout's sd-server.exe and exits 1 if it is still running; remote.sh runs it after a batch.
cd /d "%~dp0.." || exit /b 1
powershell -NoProfile -Command "Get-Process sd-server -EA SilentlyContinue | ? Path -eq (Join-Path (Get-Location) 'bin\sd-server.exe') | Stop-Process -Force; Start-Sleep 1; if (Get-Process sd-server -EA SilentlyContinue | ? Path -eq (Join-Path (Get-Location) 'bin\sd-server.exe')) { exit 1 }"
