@echo off
setlocal

set "ROOT=%~dp0"
set "HANDLER=%ROOT%abrir-msgm-folder.ps1"

if not exist "%HANDLER%" (
  echo Handler nao encontrado:
  echo %HANDLER%
  pause
  exit /b 1
)

reg add "HKCU\Software\Classes\msgm-folder" /ve /d "URL:msgm-folder Protocol" /f >nul
reg add "HKCU\Software\Classes\msgm-folder" /v "URL Protocol" /d "" /f >nul
reg add "HKCU\Software\Classes\msgm-folder\DefaultIcon" /ve /d "explorer.exe,0" /f >nul
reg add "HKCU\Software\Classes\msgm-folder\shell\open\command" /ve /d "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%HANDLER%\" \"%%1\"" /f >nul

echo Protocolo msgm-folder instalado para este usuario.
echo.
echo Teste:
echo msgm-folder://open/220526-1003_msgm_obsidian
echo.
pause
