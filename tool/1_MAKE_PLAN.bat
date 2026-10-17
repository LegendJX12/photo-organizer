@echo off
chcp 65001 >nul
REM Read-only: plan dates, folders and exact duplicates
echo Read-only: plan dates, folders and exact duplicates...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0plan.ps1" 
pause
