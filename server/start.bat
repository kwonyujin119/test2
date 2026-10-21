@echo off
chcp 65001 >nul
cd /d "%~dp0"
title ICTC 보드 서버
where python >nul 2>nul
if errorlevel 1 (
  echo [오류] Python 이 설치되어 있지 않습니다.
  echo https://www.python.org/downloads/ 에서 설치하세요. 설치 시 "Add python.exe to PATH" 를 반드시 체크.
  pause
  exit /b 1
)
python ictc_server.py %*
pause
