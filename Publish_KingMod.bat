@echo off
setlocal
title Build and publish KingMod
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publish_KingMod.ps1"
if errorlevel 1 (echo Publish failed. Review the messages above. & pause & exit /b 1)
echo KingMod is published. Installed clients will detect the update.
pause
