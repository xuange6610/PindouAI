@echo off
setlocal
chcp 65001 >nul
set "APP_ROOT=%~dp0"
set "APP_ROOT=%APP_ROOT:~0,-1%"
set "APP_EXE=%APP_ROOT%\build\windows\x64\runner\Release\bead_ai_designer.exe"

echo 正在启动拼豆 AI 设计，请稍候...
if not exist "%APP_EXE%" (
  echo 没有找到 Windows 程序，请把这个窗口中的提示发给我。
  pause
  exit /b 1
)

start "" "%APP_EXE%"
if errorlevel 1 (
  echo 启动失败，请把这个窗口中的提示发给我。
  pause
  exit /b 1
)
exit /b 0
