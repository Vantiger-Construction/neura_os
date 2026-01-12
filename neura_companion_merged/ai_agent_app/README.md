# 🤖 Neura AI Agent

An interactive console AI assistant powered by GitHub Models that helps improve the Neura Companion app faster and safer.

## Features

- �� **AI Search & Research** - Research AI/ML solutions and best practices
- 💻 **Code Generation** - Generate Flutter/Dart code for new features
- 🐛 **Debug & Fix Issues** - Analyze and fix bugs in Neura Companion
- 📈 **Performance Optimization** - Get optimization suggestions
- 🎯 **Feature Suggestions** - Innovative feature ideas for Neura
- 📚 **Learn & Documentation** - Educational resources and best practices
- ⚙️ **Settings & Configuration** - Customize agent behavior

## Prerequisites

- Python 3.8 or higher
- GitHub Personal Access Token with models scope

## Installation

1. **Clone or navigate to the ai_agent_app directory**
   `ash
   cd neura_companion_merged/ai_agent_app
   `

2. **Install dependencies**
   `ash
   pip install -r requirements.txt
   `

3. **Set up GitHub Token**
   
   **Option A: Environment Variable**
   `ash
   export GITHUB_TOKEN=your_github_token_here
   `
   
   **Option B: Create .env file**
   `ash
   echo "GITHUB_TOKEN=your_github_token_here" > .env
   `

## Getting a GitHub Token

1. Go to [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens)
2. Click "Generate new token (classic)"
3. Select the models scope
4. Copy the generated token

## Usage

Run the interactive AI agent:

`ash
python main.py
`

The agent will guide you through various options to help improve Neura Companion.

## Architecture

- **Framework**: Microsoft Agent Framework (Python)
- **Model**: GitHub Models (GPT-4o-mini via free tier)
- **UI**: Rich console interface for better user experience
- **Context**: Pre-loaded with Neura Companion app knowledge

## Capabilities

The AI agent can help with:

- Flutter/Dart code generation and optimization
- AI/ML feature implementation
- Bug analysis and debugging
- Performance optimization suggestions
- Security best practices
- Architecture design decisions
- Testing strategies
- Documentation and learning resources

## Integration with Neura Companion

This AI agent is specifically designed to:
- Understand Neura Companion's architecture and features
- Provide context-aware suggestions
- Generate code that fits existing patterns
- Suggest improvements aligned with the app's goals
- Help implement AI features to make Neura smarter

## Troubleshooting

**"GITHUB_TOKEN environment variable not found"**
- Make sure you've set the GITHUB_TOKEN environment variable
- Check that your GitHub token has the models scope

**Import errors**
- Ensure all dependencies are installed: pip install -r requirements.txt
- Use Python 3.8 or higher

**Model access issues**
- Verify your GitHub token is valid and has the correct permissions
- Check GitHub Models availability in your region

## Contributing

This AI agent is designed to help improve Neura Companion. Suggestions for new features or improvements are welcome!

## License

Part of the Neura Companion project.
