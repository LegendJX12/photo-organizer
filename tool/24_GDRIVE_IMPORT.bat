@echo off
chcp 65001 >nul
REM Copy chosen Drive files into photos
echo Copy chosen Drive files into photos...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gdrive_import.ps1" 
pause
