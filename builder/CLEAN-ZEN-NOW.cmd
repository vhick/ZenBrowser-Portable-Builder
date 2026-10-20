@echo off
setlocal
cd /d "%~dp0"
echo ==============================================================
echo  ZEN BROWSER PORTABLE - CHECK AND CLEAN
 echo  This utility NEVER closes the browser or deletes your profile.
echo ==============================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CLEAN-ZEN-NOW.ps1"
set "exitCode=%ERRORLEVEL%"
echo.
if not "%exitCode%"=="0" (
  echo Cleanup did not complete. Read the explanation above.
) else (
  echo Finished checking. Review the cleanup log and remaining files.
)
echo.
pause
exit /b %exitCode%
