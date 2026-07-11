@echo off
REM Convenience wrapper so bootstrap.ps1 can be double-clicked or run from cmd.
REM Passes through any arguments, e.g.:  bootstrap.bat -Serve -Port 8520
powershell -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" %*
pause
