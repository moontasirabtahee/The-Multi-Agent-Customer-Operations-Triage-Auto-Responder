@echo off
echo =========================================================================
echo               STARTING CLOUDFLARE SECURE REVERSE TUNNEL (DJANGO)
echo =========================================================================
echo Pointing public HTTP traffic to local Django API service on port 8520...
echo.
echo Make sure cloudflared is installed on your system.
echo Download it from: https://github.com/cloudflare/cloudflared/releases
echo.
cloudflared tunnel --url http://127.0.0.1:8520
pause
