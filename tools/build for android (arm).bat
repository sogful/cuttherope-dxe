@echo off
setlocal
set "ANDROID_HOME=C:\Users\Admin\AppData\Local\Android\Sdk"
set "SDK=%ANDROID_HOME%"
set "PROJ=%~dp0..\src\CutTheRopeDX.csproj"
set "CONFIG=Debug"
if /I "%~1"=="release" set "CONFIG=Release"

echo.
echo building %CONFIG%..
echo log: %~dp0build-android-arm.log
echo.

dotnet build "%PROJ%" -c %CONFIG% ^
  -p:CtrAndroidOnly=true ^
  -p:AndroidSdkDirectory="%SDK%" ^
  -p:EmbedAssembliesIntoApk=true ^
  -p:DebugSymbols=false ^
  -p:DebugType=none ^
  -p:AndroidPackageFormat=apk ^
  -p:RunAOTCompilation=false ^
  -nodeReuse:false ^
  -flp:LogFile="%~dp0build-android-arm.log";Verbosity=normal

set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
  echo done!
  for /f "delims=" %%F in ('dir /b /s /a-d "%~dp0..\bin\%CONFIG%\net9.0-android\*-Signed.apk" 2^>nul') do (
    copy /y "%%F" "%~dp0..\bin\CutTheRope-DX-arm.apk" >nul
    echo at: %~dp0..\bin\CutTheRope-DX-arm.apk  ^(%%~zF bytes^)
  )
) else (
  echo build failed.. ^(exit %RESULT%^) - see build-android-arm.log
)
powershell -NoProfile -Command "[console]::beep(1046,180); [console]::beep(1568,320)"
endlocal
