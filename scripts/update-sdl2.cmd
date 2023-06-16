@ECHO OFF
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy ByPass -Command "& """%~dp0update-sdl2.ps1""" %*"
EXIT /B %ERRORLEVEL%
