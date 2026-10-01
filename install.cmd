@echo off
setlocal DisableDelayedExpansion
call "%~dp0scripts\manage.cmd" install "%~1" "%~2"
set "result=%errorlevel%"
if "%~1"=="" pause
exit /b %result%
