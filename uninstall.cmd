@echo off
setlocal DisableDelayedExpansion
call "%~dp0scripts\manage.cmd" uninstall "%~1"
set "result=%errorlevel%"
if "%~1"=="" pause
exit /b %result%
