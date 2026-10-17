@echo off
chcp 65001 >nul
REM Undo step 10
echo Undo step 10...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0undo_trips.ps1" 
pause
