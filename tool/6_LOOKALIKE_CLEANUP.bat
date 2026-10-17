@echo off
chcp 65001 >nul
REM Recycle lower-quality look-alike copies
echo Recycle lower-quality look-alike copies...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lookalike_cleanup.ps1" 
pause
