@echo off
setlocal
cd /d "%~dp0"

set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL_EXE%" set "POWERSHELL_EXE=powershell.exe"

"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\update_project.ps1"
set "SCRIPT_EXIT=%ERRORLEVEL%"

echo.
if "%SCRIPT_EXIT%"=="0" (
  echo Project update finished successfully.
) else (
  echo Project update failed. Please keep this window open and send the error above to a developer.
)
echo.
pause
exit /b %SCRIPT_EXIT%
