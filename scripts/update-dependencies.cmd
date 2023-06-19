@ECHO OFF
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy ByPass -Command "& """%~dp0update-dependencies.ps1""" %*"
EXIT /B %ERRORLEVEL%
