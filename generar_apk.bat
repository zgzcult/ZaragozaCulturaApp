@echo off
setlocal
set GRADLE_USER_HOME=C:\gradle_home
set PATH=C:\flutter\bin;%PATH%

echo ============================================
echo  Generando APK de Zaragoza Cultura App...
echo  (esto puede tardar varios minutos)
echo ============================================
echo.

cd /d "%~dp0"
call flutter pub get
call flutter build apk --release

echo.
if exist "build\app\outputs\flutter-apk\app-release.apk" (
    echo ============================================
    echo  LISTO. El APK esta en:
    echo  %~dp0build\app\outputs\flutter-apk\app-release.apk
    echo ============================================
) else (
    echo ============================================
    echo  Algo fallo. Revisa los mensajes de arriba.
    echo ============================================
)

pause
