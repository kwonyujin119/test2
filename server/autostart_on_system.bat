@echo off
chcp 65001 >nul
cd /d "%~dp0"
title SAIL:41 서버 자동 시작 등록 (로그인 없이)
echo PC 전원이 켜지면 로그인하지 않아도 SAIL:41 서버가 켜지도록 등록합니다. (SYSTEM 계정, 창 없이 백그라운드)
echo 관리자 권한이 필요합니다. 실패하면 마우스 오른쪽 → "관리자 권한으로 실행".
schtasks /create /f /tn "SAIL41 서버" /sc onstart /delay 0000:30 /ru SYSTEM /rl highest /tr "\"%~dp0start.bat\" --auto"
if errorlevel 1 (
  echo [오류] 등록에 실패했습니다. 관리자 권한으로 다시 실행하세요.
) else (
  echo 등록됐습니다. 다음 부팅부터 자동으로 켜집니다. 창이 안 보이는 대신 서버 메시지는 %~dp0server.log 에 남습니다.
  echo 지금 바로 켜려면: schtasks /run /tn "SAIL41 서버"
)
pause
