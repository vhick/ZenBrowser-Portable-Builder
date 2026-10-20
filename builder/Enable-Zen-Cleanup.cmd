@echo off
setlocal
set "SCRIPT=%~dp0ZenUpdateCleanup.ps1"
set "ROOT=%~dp0.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Configure -Root "%ROOT%"
echo.
echo Press any key to close this window.
pause >nul
