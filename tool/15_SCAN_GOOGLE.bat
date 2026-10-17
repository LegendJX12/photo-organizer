@echo off
chcp 65001 >nul
REM Read-only: scan the Takeout photos
echo Read-only: scan the Takeout photos...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0takeout_scan.ps1" 
pause
