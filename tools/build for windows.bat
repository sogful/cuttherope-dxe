@echo off
setlocal
set "PROJ=%~dp0..\src\CutTheRopeDX.csproj"
set "CONFIG=Debug"
if /I "%~1"=="release" set "CONFIG=Release"

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
  if /I "%CONFIG%"=="Release" (
    echo at: %~dp0..\bin\Release\net9.0\win-x64\publish\CutTheRope-DX.exe
  ) else (
    echo at: %~dp0..\bin\Debug\net9.0\CutTheRope-DX.exe
  )
) else (
  echo build failed.. ^(exit %RESULT%^) - see build-windows.log
)
powershell -NoProfile -Command "[console]::beep(1046,180); [console]::beep(1568,320)"
endlocal
