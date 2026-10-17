@echo off
chcp 65001 >nul
REM Merge year folders (merge_years.csv)
echo Merge year folders (merge_years.csv)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0merge_years.ps1" 
pause
