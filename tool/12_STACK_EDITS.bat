@echo off
chcp 65001 >nul
REM Apply your stack review
echo Apply your stack review...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stack_edits.ps1" 
pause
