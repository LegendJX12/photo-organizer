@echo off
chcp 65001 >nul
REM Move trips into folders + stack similar shots
echo Move trips into folders + stack similar shots...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0trips_and_stacks.ps1" 
pause
