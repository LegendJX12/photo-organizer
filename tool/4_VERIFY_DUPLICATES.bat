@echo off
chcp 65001 >nul
REM Read-only: re-check duplicates with SHA256
echo Read-only: re-check duplicates with SHA256...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" 
pause
