@echo off
chcp 65001 > nul
setlocal
cd /d "%~dp0"
echo.
echo   HAAVK boot animation - DSH plugin installer
echo   -------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
