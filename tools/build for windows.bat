@echo off
setlocal
set "PROJ=%~dp0..\src\CutTheRopeDX.csproj"
set "CONFIG=Debug"
if /I "%~1"=="release" set "CONFIG=Release"

if /I "%CONFIG%"=="Release" (
  set "OUT=%~dp0bin\Release\net9.0\win-x64\publish\CutTheRope-DX.exe"
) else (
  set "OUT=%~dp0bin\Debug\net9.0\CutTheRope-DX.exe"
)

echo.
echo building windows %CONFIG%..
echo log: %~dp0build-windows.log
echo.

if /I "%CONFIG%"=="Release" (
  dotnet publish "%PROJ%" -c Release -f net9.0 -r win-x64 ^
    -nodeReuse:false ^
    -flp:LogFile="%~dp0build-windows.log";Verbosity=normal
) else (
  dotnet build "%PROJ%" -c Debug -f net9.0 ^
    -nodeReuse:false ^
    -flp:LogFile="%~dp0build-windows.log";Verbosity=normal
)

set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
  echo done!
  echo at: %OUT%
) else (
  echo build failed.. ^(exit %RESULT%^) - see build-windows.log
)
powershell -NoProfile -Command "[console]::beep(1046,180); [console]::beep(1568,320)"

if not "%RESULT%"=="0" goto :end
set /p "OPENIT=open the build now? (y/n): "
if /I "%OPENIT%"=="y" start "" "%OUT%"
:end
endlocal
