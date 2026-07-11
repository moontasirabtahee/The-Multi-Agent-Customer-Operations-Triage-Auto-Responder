@echo off
echo =========================================================================
echo               STARTING CLOUDFLARE SECURE REVERSE TUNNEL
echo =========================================================================
echo Pointing public HTTP traffic to local Django API service on port 8000...
echo.
echo Make sure cloudflared is installed on your system.
echo Download it from: https://github.com/cloudflare/cloudflared/releases
echo.
cloudflared tunnel --url http://localhost:8000
pause
