@echo off
rem Double-click to junction ForeverUI into the Forever beta and set up git.
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0link.ps1"
if not exist ".git" (git init -b main)
echo.
echo Done. You can close this window.
pause
