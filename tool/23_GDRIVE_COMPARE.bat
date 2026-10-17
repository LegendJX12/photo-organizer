@echo off
chcp 65001 >nul
REM Read-only: what in Google Drive is not in photos
echo Read-only: what in Google Drive is not in photos...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gdrive_compare.ps1" 
pause
