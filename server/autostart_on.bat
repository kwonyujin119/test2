@echo off
chcp 65001 >nul
cd /d "%~dp0"
title SAIL:41 서버 자동 시작 등록
echo PC 에 로그인하면 SAIL:41 서버가 자동으로 켜지도록 등록합니다. (현재 사용자, 30초 뒤 시작, 꺼지면 5초 뒤 재시작)
schtasks /create /f /tn "SAIL41 서버" /sc onlogon /delay 0000:30 /rl highest /tr "\"%~dp0start.bat\" --auto"
if errorlevel 1 (
  echo [오류] 등록에 실패했습니다. 이 파일을 마우스 오른쪽 → "관리자 권한으로 실행" 으로 다시 실행하세요.
) else (
  echo 등록됐습니다. 다음 로그인부터 자동으로 켜집니다. 지금 바로 켜려면 start.bat 을 실행하세요.
  echo 해제하려면 autostart_off.bat 을 실행하세요.
)
pause
