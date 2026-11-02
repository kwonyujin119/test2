@echo off
chcp 65001 >nul
title SAIL:41 서버 자동 시작 해제
schtasks /delete /f /tn "SAIL41 서버"
if errorlevel 1 ( echo 등록된 자동 시작이 없거나 권한이 없습니다. ) else ( echo 자동 시작을 해제했습니다. 켜져 있는 서버는 창을 닫으면 꺼집니다. )
pause
