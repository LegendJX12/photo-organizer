@echo off
chcp 65001 >nul
REM Unzip every .zip in the photos folder
echo Unzip every .zip in the photos folder...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0extract.ps1" 
pause
