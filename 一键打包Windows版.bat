@echo off
setlocal
cd /d "%~dp0"

set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL_EXE%" set "POWERSHELL_EXE=powershell.exe"

"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\build_windows.ps1"
set "SCRIPT_EXIT=%ERRORLEVEL%"

echo.
if "%SCRIPT_EXIT%"=="0" (
  echo Windows package finished successfully.
) else (
  echo Windows package failed. Please keep this window open and send the error above to a developer.
)
echo.
pause
exit /b %SCRIPT_EXIT%
