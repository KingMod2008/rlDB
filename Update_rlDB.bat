@echo off
setlocal EnableExtensions
chcp 65001 >nul
title KingMod Database Updater
set "SOURCE=%~dp0"
set "WORK=%TEMP%\KingMod_rlDB_%RANDOM%_%RANDOM%"
where git >nul 2>&1 || (echo ERROR: Install Git first. & goto :fail)
echo Cloning KingMod2008/rlDB...
git clone --depth 1 https://github.com/KingMod2008/rlDB.git "%WORK%" || goto :fail
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SOURCE%Prepare_rlDB.ps1" -Destination "%WORK%" || goto :fail
pushd "%WORK%" || goto :fail
git add --all || (popd & goto :fail)
git diff --cached --quiet
if not errorlevel 1 (popd & goto :done)
git commit -m "Update KingMod catalogs, plugin folders, images and patch collections" || (popd & goto :fail)
git push origin HEAD:main || (popd & goto :fail)
popd
:done
echo SUCCESS: KingMod database published. Your original files were preserved.
echo Recoverable checkout: %WORK%
pause
exit /b 0
:fail
echo FAILED: Nothing in your source folder was deleted.
echo Review the messages above. Temporary checkout: %WORK%
pause
exit /b 1
