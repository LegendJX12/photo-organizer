@echo off
chcp 65001 >nul
REM Read-only: your own Drive files vs photos
echo Read-only: your own Drive files vs photos...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0drive_owned.ps1" 
pause
