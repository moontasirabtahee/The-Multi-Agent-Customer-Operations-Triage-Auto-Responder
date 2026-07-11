@echo off
echo =========================================================================
echo            STARTING CLOUDFLARE SECURE REVERSE TUNNEL (OLLAMA LLM)
echo =========================================================================
echo Pointing public HTTP traffic to local Ollama inference server on port 11434...
echo.
echo NOTE: --http-host-header rewrites the Host header to localhost:11434 so that
echo       Ollama accepts the proxied request (it rejects non-local Host headers).
echo Make sure Ollama is running (OLLAMA_HOST=0.0.0.0) before starting this tunnel.
echo.
cloudflared tunnel --url http://127.0.0.1:11434 --http-host-header localhost:11434
pause
