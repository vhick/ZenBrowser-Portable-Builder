@echo off
setlocal
set "CONFIG=%~dp0..\Data\UpdaterCleanup\approved-update-folder.txt"
if exist "%CONFIG%" (
    del "%CONFIG%"
    echo Optional Zen updater cleanup is now OFF. Verified Start Menu shortcut cleanup stays ON.
) else (
    echo ProgramData updater cleanup was already OFF. Verified shortcut cleanup stays ON.
)
echo.
pause
