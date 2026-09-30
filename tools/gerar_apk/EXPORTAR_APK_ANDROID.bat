@echo off
setlocal
rem SWISH_BUILD=1
rem Script interno: quem chama e o GERAR_APK_AGORA.bat (na raiz), pelo
rem GERAR_APK_COMPLETO.ps1, que ja deixa o Godot 3.6.2, o modelo Android, o
rem plugin USB, o Java e a chave de assinatura prontos.
cd /d "%~dp0..\.."

if "%~1"=="" (
  echo USO: EXPORTAR_APK_ANDROID.bat "C:\caminho\Godot_v3.6.2-stable_win64.exe"
  exit /b 2
)
if not exist "%~1" (
  echo ERRO: executavel do Godot nao encontrado: %~1
  exit /b 2
)
if not exist "android\plugins\DragonUsbSerial-release.aar" (
  echo ERRO: plugin USB nao encontrado em android\plugins.
  exit /b 3
)
if not exist "android\build\build.gradle" (
  echo ERRO: modelo Android do Godot 3.6.2 nao encontrado em android\build.
  exit /b 4
)

if not exist "build\android" mkdir "build\android"
if exist "build\android\SwishArena-S905L.apk" del /q "build\android\SwishArena-S905L.apk"

rem 1) IMPORTACAO SEM GRADLE. Numa pasta nova o Godot 3 le os scripts dos
rem autoloads ANTES de importar sons e imagens; montar so o pacote (.pck)
rem primeiro importa tudo com calma, sem o Gradle no meio. O .pck e jogado
rem fora depois.
set "LOG=build\android\exportacao.log"
echo [a] Importando imagens, sons e cenas (primeira vez demora)...
"%~1" --no-window --path "%CD%" --export-pack "Android" "build\android\importacao.pck" > "%LOG%" 2>&1
if exist "build\android\importacao.pck" del /q "build\android\importacao.pck"

rem 2) O APK (Gradle + plugin USB). APK DE RELEASE: bibliotecas nativas
rem otimizadas e GDScript sem as checagens de depuracao. Tudo o que o Godot
rem e o Gradle escrevem vai para build\android\exportacao.log.
echo [b] Montando o APK com o Gradle (alguns minutos)...
"%~1" --no-window --path "%CD%" --export "Android" "build\android\SwishArena-S905L.apk" >> "%LOG%" 2>&1
if not exist "build\android\SwishArena-S905L.apk" (
  echo     Nao saiu na primeira. Tentando mais uma vez...
  "%~1" --no-window --path "%CD%" --export "Android" "build\android\SwishArena-S905L.apk" >> "%LOG%" 2>&1
)
if not exist "build\android\SwishArena-S905L.apk" (
  echo ERRO: o Godot terminou sem criar o APK. Detalhes em %LOG%
  exit /b 6
)
echo APK criado em build\android\SwishArena-S905L.apk
exit /b 0
