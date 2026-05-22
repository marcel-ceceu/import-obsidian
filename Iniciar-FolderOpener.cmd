@echo off
cd /d "%~dp0"
where node >nul 2>&1 || (
  echo Node.js nao encontrado. Instale Node LTS.
  pause
  exit /b 1
)
start "folder-opener-5380" /min node "%~dp0folder-opener.mjs"
echo Helper folder-opener iniciado em http://127.0.0.1:5380
timeout /t 2 >nul
