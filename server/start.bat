@echo off
chcp 65001 >nul
cd /d "%~dp0"
title 지휘역량강화센터 일정·업무 보드 서버
set "DATA_DIR=D:\일정표,주요업무"
set "PY="
python --version >nul 2>nul && set "PY=python"
if not defined PY ( py -3 --version >nul 2>nul && set "PY=py -3" )
if not defined PY (
  echo [오류] Python 이 설치되어 있지 않거나 PATH 에 없습니다.
  echo  1. https://www.python.org/downloads/ 에서 설치 - 첫 화면의 "Add python.exe to PATH" 체크
  echo  2. 설치 후 이 파일을 다시 실행
  echo  * "python" 입력 시 Microsoft Store 가 열리면: 설정 - 앱 - 고급 앱 설정 - 앱 실행 별칭에서 python 항목을 끄세요.
  pause
  exit /b 1
)
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"
if not exist "%DATA_DIR%" (
  echo [오류] 데이터 폴더를 만들 수 없습니다: %DATA_DIR%  ^(D 드라이브가 있는지 확인^)
  pause
  exit /b 1
)
%PY% ictc_server.py --db "%DATA_DIR%\ictc.db" --pin-file "%DATA_DIR%\pin.txt" %*
echo.
echo 서버가 종료되었습니다. 창을 닫아도 됩니다.
pause
