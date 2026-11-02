@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "AUTO="
if /i "%~1"=="--auto" set "AUTO=1"
title SAIL:41 일정·업무 보드 서버
set "DATA_DIR=D:\일정표,주요업무"
set "PY="
python --version >nul 2>nul && set "PY=python"
if not defined PY ( py -3 --version >nul 2>nul && set "PY=py -3" )
if not defined PY (
  echo [오류] Python 이 설치되어 있지 않거나 PATH 에 없습니다.
  echo  1. https://www.python.org/downloads/ 에서 설치 - 첫 화면의 "Add python.exe to PATH" 체크
  echo  2. 설치 후 이 파일을 다시 실행
  echo  * "python" 입력 시 Microsoft Store 가 열리면: 설정 - 앱 - 고급 앱 설정 - 앱 실행 별칭에서 python 항목을 끄세요.
  if defined AUTO ( echo [%date% %time%] 시작 실패 - 위 안내를 확인하세요 >> "%~dp0server.log" ) else pause
  exit /b 1
)
if not exist "ictc_server.py" (
  echo [오류] 이 폴더에 ictc_server.py 가 없습니다. ZIP 을 전부 풀고 start.bat 을 그 폴더에서 실행하세요.
  if defined AUTO ( echo [%date% %time%] 시작 실패 - 위 안내를 확인하세요 >> "%~dp0server.log" ) else pause
  exit /b 1
)
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"
if not exist "%DATA_DIR%" (
  echo [오류] 데이터 폴더를 만들 수 없습니다: %DATA_DIR%  ^(D 드라이브가 있는지 확인^)
  if defined AUTO ( echo [%date% %time%] 시작 실패 - 위 안내를 확인하세요 >> "%~dp0server.log" ) else pause
  exit /b 1
)
if defined AUTO goto auto
%PY% ictc_server.py --db "%DATA_DIR%\ictc.db" --pin-file "%DATA_DIR%\pin.txt" %*
echo.
echo 서버가 종료되었습니다. 창을 닫아도 됩니다.
pause
exit /b

:auto
rem 자동 시작 모드(autostart_on.bat 이 등록한 예약 작업이 호출): 꺼지면 5초 뒤 다시 켜고, 메시지는 server.log 에도 남긴다
:loop
echo [%date% %time%] 서버 시작 >> "%~dp0server.log"
%PY% ictc_server.py --db "%DATA_DIR%\ictc.db" --pin-file "%DATA_DIR%\pin.txt" >> "%~dp0server.log" 2>&1
echo [%date% %time%] 서버 종료(코드 %errorlevel%) - 5초 뒤 재시작 >> "%~dp0server.log"
timeout /t 5 /nobreak >nul
goto loop
