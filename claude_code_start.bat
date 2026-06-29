@echo off
cd /d "%~dp0"

where claude >nul 2>nul
if errorlevel 1 (
    echo Claude Code CLI not found. Install it with:
    echo     npm install -g @anthropic-ai/claude-code
    pause
    exit /b 1
)

claude
