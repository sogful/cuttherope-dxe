@echo off
setlocal
set "PROJ=%~dp0..\..\..\src\CutTheRopeDX.Android\CutTheRopeDX.Android.csproj"
set "OUT=%~dp0bin\CutTheRope-DX-arm.apk"
set "CONFIG=Debug"
if /I "%~1"=="release" set "CONFIG=Release"

echo.
echo building %CONFIG%..
echo log: %~dp0build-android-arm.log
echo.

dotnet build "%PROJ%" -c %CONFIG% ^
  -p:RuntimeIdentifier=android-arm64 ^
  -p:BaseOutputPath="%~dp0bin\" ^
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
  for /f "delims=" %%F in ('dir /b /s /a-d "%~dp0bin\%CONFIG%\net10.0-android36.0\*-Signed.apk" 2^>nul') do (
    copy /y "%%F" "%OUT%" >nul
    echo at: %OUT%  ^(%%~zF bytes^)
  )
) else (
  echo build failed.. ^(exit %RESULT%^) - see build-android-arm.log
)
powershell -NoProfile -Command "[console]::beep(1046,180); [console]::beep(1568,320)"

if not "%RESULT%"=="0" goto :end
if not exist "%OUT%" goto :end
set /p "OPENIT=open the apk now? (y/n): "
if /I "%OPENIT%"=="y" start "" "%OUT%"
:end
endlocal
