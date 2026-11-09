@echo off
setlocal
set "NOKI_UPDATER=%TEMP%\NokiForeverUpdater-%RANDOM%-%RANDOM%.ps1"
echo Downloading the latest updater from GitHub...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/PyNoki/nokiForever/main/NokiForeverUpdater/Updater.ps1' -OutFile $env:NOKI_UPDATER"
if errorlevel 1 goto failed
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NOKI_UPDATER%"
set "NOKI_EXIT=%ERRORLEVEL%"
del "%NOKI_UPDATER%" 2>nul
if not "%NOKI_EXIT%"=="0" goto failed
pause
exit /b 0
:failed
echo The updater could not finish. Check your connection and try again.
pause
exit /b 1

