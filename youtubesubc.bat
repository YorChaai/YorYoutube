@echo off
title Personal YouTube Subscriptions Hub
echo ========================================================
echo   Menjalankan Personal YouTube Hub di http://localhost:8000
echo ========================================================
where.exe adb >nul 2>&1
if not errorlevel 1 adb -d reverse tcp:8000 tcp:8000 >nul 2>&1
start /b powershell -NoProfile -WindowStyle Hidden -Command "for ($i=0; $i -lt 60; $i++) { try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/api/settings' -UseBasicParsing -TimeoutSec 1; if ($r.StatusCode -eq 200) { Start-Process 'http://localhost:8000'; break } } catch {}; Start-Sleep -Milliseconds 300 }"
cd /d %~dp0backend
python -m uvicorn main:app --host 0.0.0.0 --port 8000
