@echo off
chcp 65001 >nul
REM Move files as planned (writes undo.csv)
echo Move files as planned (writes undo.csv)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply.ps1" 
pause
