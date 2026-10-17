@echo off
chcp 65001 >nul
REM Copy Google-only photos into your folders
echo Copy Google-only photos into your folders...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0google_import.ps1" 
pause
