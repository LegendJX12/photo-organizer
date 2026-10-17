@echo off
chcp 65001 >nul
REM Check and unzip Google Takeout zips
echo Check and unzip Google Takeout zips...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0takeout_unzip.ps1" 
pause
