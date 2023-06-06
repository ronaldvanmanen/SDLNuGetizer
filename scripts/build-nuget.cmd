@ECHO OFF
powershell.exe -NoLogo -NoProfile -ExecutionPolicy ByPass -Command "& """%~dp0build-nuget.ps1""" %*"
EXIT /B %ERRORLEVEL%
