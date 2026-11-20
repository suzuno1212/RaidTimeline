@echo off
rem RaidTimelineTool - build the exe with PyInstaller
rem Output: dist\RaidTimelineTool\RaidTimelineTool.exe
cd /d "%~dp0"
python -m pip install --upgrade pyinstaller pywebview
if errorlevel 1 goto fail
python -m PyInstaller --noconfirm RaidTimelineTool.spec
if errorlevel 1 goto fail
echo.
echo OK: dist\RaidTimelineTool\RaidTimelineTool.exe
pause
exit /b 0
:fail
echo.
echo FAILED
pause
exit /b 1
