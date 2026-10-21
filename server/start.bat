@echo off
chcp 65001 >nul
cd /d "%~dp0"
title ICTC 일정·업무 보드 서버
set "DATA_DIR=D:\일정표,주요업무"
where python >nul 2>nul
if errorlevel 1 (
  echo [오류] Python 이 설치되어 있지 않습니다.
  echo https://www.python.org/downloads/ 에서 설치하세요. 설치 시 "Add python.exe to PATH" 를 반드시 체크.
  pause
  exit /b 1
)
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"
python ictc_server.py --db "%DATA_DIR%\ictc.db" --pin-file "%DATA_DIR%\pin.txt" %*
pause
