@echo off
chcp 65001 >nul
REM Stack similar shots among imported photos
echo Stack similar shots among imported photos...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stacks_new.ps1" 
pause
