@echo off
chcp 65001 >nul
REM Clean up OneDrive leftovers (onedrive_actions.csv)
echo Clean up OneDrive leftovers (onedrive_actions.csv)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0onedrive_apply.ps1" 
pause
