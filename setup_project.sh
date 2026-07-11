#!/bin/bash

echo "========================================================================="
echo "      Project Setup: Multi-Agent Customer Operations Triage & Auto-Responder"
echo "========================================================================="
echo

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "[ERROR] Python 3 is not installed. Please install Python 3.10+ and try again."
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
    echo "Creating Python virtual environment in .venv..."
    python3 -m venv .venv
    if [ $? -ne 0 ]; then
        echo "[ERROR] Failed to create virtual environment."
        exit 1
    fi
else
    echo "Virtual environment .venv already exists."
fi

# Upgrade pip and install dependencies
echo
echo "Installing and upgrading dependencies..."
.venv/bin/python -m pip install --upgrade pip
.venv/bin/pip install -r requirements.txt

if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to install dependencies."
    exit 1
fi

# Setup .env file if it doesn't exist
if [ ! -f "backend/.env" ]; then
    echo
    echo "Creating default backend/.env configuration file..."
    cp backend/.env.example backend/.env
    echo "Please configure your target PC's environment variables in backend/.env."
fi

echo
echo "========================================================================="
echo "[SUCCESS] Setup complete! Virtual environment created and packages installed."
echo "========================================================================="
