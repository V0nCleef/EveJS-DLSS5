@echo off
setlocal
set "PSModulePath="
if "%~1"=="" (
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-Standalone.ps1" -Action Runtime %*
) else (
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-Standalone.ps1" -Action Runtime -ProcessId "%~1" -ReShadeBasePath "%~2"
)
set "EVEJS_DLSS5_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %EVEJS_DLSS5_EXIT%
