@echo off
chcp 65001 >nul
REM Read-only: check files OneDrive brought back
echo Read-only: check files OneDrive brought back...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0onedrive_check.ps1" 
pause
