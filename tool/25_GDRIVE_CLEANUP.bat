@echo off
chcp 65001 >nul
REM Delete Drive files that are safely copied
echo Delete Drive files that are safely copied...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gdrive_cleanup.ps1" 
pause
