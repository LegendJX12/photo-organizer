@echo off
chcp 65001 >nul
REM Recycle verified duplicates, then look for look-alikes
echo Recycle verified duplicates, then look for look-alikes...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0clean_and_rescan.ps1" 
pause
