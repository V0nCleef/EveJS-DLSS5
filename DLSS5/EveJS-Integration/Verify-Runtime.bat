@echo off
setlocal
set "PSModulePath="
if "%~1"=="" (
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-Standalone.ps1" -Action Runtime %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage-EveJSDLSS5.ps1" -Action Runtime -ProcessId "%~1"
)
set "EVEJS_DLSS5_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %EVEJS_DLSS5_EXIT%
