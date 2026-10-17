@echo off
chcp 65001 >nul
REM Copy missing, then delete only backed-up own files
echo Copy missing, then delete only backed-up own files...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0drive_owned.ps1" -Apply
pause
