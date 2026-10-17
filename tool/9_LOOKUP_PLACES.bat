@echo off
chcp 65001 >nul
REM Look up place names (OpenStreetMap)
echo Look up place names (OpenStreetMap)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0geocode.ps1" 
pause
