@echo off
setlocal
rem SWISH_BUILD=1
title Swish Arena - Gerar APK da TV Box (TX9 / Mali-450)
cd /d "%~dp0"

echo ============================================================
echo   SWISH ARENA - GERAR APK DA TV BOX (TX9 / MALI-450, ANDROID 7.1+)
echo   GODOT 3.6 (OPENGL ES 2.0) + PLUGIN USB DO ARDUINO
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\gerar_apk\GERAR_APK_COMPLETO.ps1"
if errorlevel 1 (
  echo.
  echo FALHA: o APK nao foi criado. Fotografe esta janela inteira.
  pause
  exit /b 1
)

echo.
echo SUCESSO. APK pronto na pasta APK-Pronto (o nome tem a versao):
dir /b "%~dp0APK-Pronto\*.apk"
echo.
echo Copie o APK para o pendrive e instale na TV Box.
start "" "%~dp0APK-Pronto"
pause
exit /b 0
