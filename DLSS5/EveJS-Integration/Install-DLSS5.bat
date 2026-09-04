@echo off
setlocal
set "PSModulePath="
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-Standalone.ps1" -Action Ensure %*
set "EVEJS_DLSS5_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %EVEJS_DLSS5_EXIT%
