@echo off
chcp 65001 >nul
REM Read-only: date, GPS and fingerprint for every photo
echo Read-only: date, GPS and fingerprint for every photo...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scan_folder.ps1" 
pause
