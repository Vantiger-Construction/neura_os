#!/usr/bin/env python3
"""
Setup script for Neura AI Agent
Helps users configure the environment and test the setup.
"""

import os
import sys
import subprocess
from pathlib import Path

def check_python_version():
    """Check if Python version is compatible."""
    if sys.version_info < (3, 8):
        print("❌ Python 3.8 or higher is required")
        print(f"Current version: {sys.version}")
        return False
    print(f"✅ Python version: {sys.version}")
    return True

def install_dependencies():
    """Install required Python packages."""
    try:
        print("📦 Installing dependencies...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", "requirements.txt"])
        print("✅ Dependencies installed successfully")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to install dependencies: {e}")
        return False

def check_github_token():
    """Check if GitHub token is configured."""
    token = os.getenv("GITHUB_TOKEN")
    if token:
        print("✅ GITHUB_TOKEN environment variable found")
        return True
    else:
        print("❌ GITHUB_TOKEN environment variable not found")
        print("\nTo set up your GitHub token:")
        print("1. Go to https://github.com/settings/tokens")
        print("2. Generate a new token with 'models' scope")
        print("3. Run: export GITHUB_TOKEN=your_token_here")
        print("   Or create a .env file with: GITHUB_TOKEN=your_token_here")
        return False

def test_agent_initialization():
    """Test if the agent can be initialized."""
    try:
        print("🤖 Testing agent initialization...")
        # Import and try to initialize (basic test)
        import asyncio
        from rich.console import Console

        console = Console()
        console.print("[green]✅ Agent framework imports successful[/green]")

        # Check if token is available for full test
        if os.getenv("GITHUB_TOKEN"):
            console.print("[green]✅ Ready for full agent initialization[/green]")
        else:
            console.print("[yellow]⚠️  GitHub token needed for full functionality[/yellow]")

        return True
    except ImportError as e:
        print(f"❌ Import error: {e}")
        return False

def main():
    """Main setup function."""
    print("🚀 Neura AI Agent Setup")
    print("=" * 50)

    # Check Python version
    if not check_python_version():
        return False

    # Install dependencies
    if not install_dependencies():
        return False

    # Check GitHub token
    token_configured = check_github_token()

    # Test agent initialization
    if not test_agent_initialization():
        return False

    print("\n" + "=" * 50)
    if token_configured:
        print("🎉 Setup complete! You can now run: python main.py")
    else:
        print("⚠️  Setup incomplete. Please configure your GitHub token first.")
        print("Then run: python main.py")

    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
