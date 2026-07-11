@echo off
echo =========================================================================
echo       Project Setup: Multi-Agent Customer Operations Triage & Auto-Responder
echo =========================================================================
echo.

:: Check if Python is installed
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python is not installed or not in PATH. Please install Python 3.10+ and try again.
    pause
    exit /b %errorlevel%
)

:: Create virtual environment if it doesn't exist
if not exist ".venv" (
    echo Creating Python virtual environment in .venv...
    python -m venv .venv
    if %errorlevel% neq 0 (
        echo [ERROR] Failed to create virtual environment.
        pause
        exit /b %errorlevel%
    )
) else (
    echo Virtual environment .venv already exists.
)

:: Upgrade pip and install dependencies
echo.
echo Installing and upgrading dependencies...
.venv\Scripts\python -m pip install --upgrade pip
.venv\Scripts\pip install django djangorestframework llama-index-core llama-index-llms-ollama llama-index-embeddings-ollama llama-index-vector-stores-postgres psycopg2-binary python-dotenv

if %errorlevel% neq 0 (
    echo [ERROR] Failed to install dependencies.
    pause
    exit /b %errorlevel%
)

:: Setup .env file if it doesn't exist
if not exist "backend\.env" (
    echo.
    echo Creating default backend\.env configuration file...
    copy "backend\.env.example" "backend\.env" >nul
    echo Please configure your target PC's environment variables in backend\.env.
)

echo.
echo =========================================================================
echo [SUCCESS] Setup complete! Virtual environment created and packages installed.
echo =========================================================================
pause
