@echo off
chcp 65001 >nul
REM Undo step 16
echo Undo step 16...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0undo_google_import.ps1" 
pause
