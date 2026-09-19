@echo off
setlocal
cd /d "%~dp0"

set "PY="
where python >nul 2>&1 && set "PY=python"
if not defined PY ( where py >nul 2>&1 && set "PY=py" )
if not defined PY (
  echo python not found, one sec, installing with winget...
  winget install -e --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
  echo.
  echo python installed, reopen this file!
  pause
  exit /b 1
)

echo installing python packages..
%PY% -m pip install --quiet --upgrade etcpak pillow numpy || goto :err

echo encoding textures..
%PY% "%~dp0create etc2 assets.py" || goto :err

echo building sound effects..
dotnet tool restore || goto :err
pushd "%~dp0..\assets"
dotnet mgcb /@:content-android.mgcb
set "MGCBRESULT=%ERRORLEVEL%"
popd
if not "%MGCBRESULT%"=="0" goto :err

echo.
echo assets generated!
powershell -NoProfile -Command "[console]::beep(1046,180); [console]::beep(1568,320)"
exit /b 0

:err
echo.
echo asset generation failed..
exit /b 1
