@echo off
chcp 65001 >nul
REM Undo step 2
echo Undo step 2...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0undo.ps1" 
pause
