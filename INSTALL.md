# EC4X Nim Installation Guide

This guide will help you install and set up the EC4X Nim version on your system.

## Prerequisites

### System Requirements

- **Operating System**: Linux, macOS, or Windows
- **Memory**: At least 512MB RAM
- **Disk Space**: 100MB for installation, additional space for games
- **Network**: Internet connection for multiplayer games (optional)

### Required Software

#### 1. Nim Compiler

EC4X requires Nim 2.0.0 or higher.

**Linux (Ubuntu/Debian):**
```bash
# Install from package manager (may not have latest version)
sudo apt update
sudo apt install nim

# Or install from choosenim (recommended)
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

**macOS:**
```bash
# Using Homebrew
brew install nim

# Or using choosenim
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

**Windows:**
1. Download installer from https://nim-lang.org/install.html
2. Run the installer and follow instructions
3. Or use choosenim: Download and run `choosenim-init.exe`

**From Source:**
```bash
git clone https://github.com/nim-lang/Nim.git
cd Nim
git checkout version-2-0
./build.sh
```

#### 2. Nimble Package Manager

Nimble usually comes with Nim. Verify installation:
```bash
nimble --version
```

If not installed, get it from: https://github.com/nim-lang/nimble

### Optional Software

- **Git**: For version control and updates
- **Make**: For using the Makefile (Linux/macOS)
- **Text Editor**: VS Code, Vim, Emacs, or any editor with Nim support

## Installation Steps

### 1. Clone the Repository

```bash
git clone https://github.com/greenm01/ec4x.git
cd ec4x/ec4x_nim
```

Or download and extract the source code archive.

### 2. Install Dependencies

```bash
# Install all required packages
nimble install -d

# Or install manually
nimble install cligen
nimble install toml_serialization
```

### 3. Build the Project

#### Option A: Using the Build Script (Recommended)
```bash
# Make executable (Linux/macOS)
chmod +x build.sh

# Build all components
./build.sh

# Build and run tests
./build.sh test
```

#### Option B: Using Make
```bash
# Install dependencies
make deps

# Build all components
make all

# Run tests
make test
```

#### Option C: Manual Build
```bash
# Create bin directory
mkdir -p bin

# Build moderator
nim c -d:release --opt:speed -o:bin/moderator src/moderator.nim

# Build client
nim c -d:release --opt:speed -o:bin/client src/client.nim

# Test core library
nim check src/ec4x_core.nim
```

### 4. Verify Installation

Check that the binaries work:
```bash
# Test moderator
./bin/moderator version

# Test client
./bin/client version

# Run tests
make test
```

## Post-Installation Setup

### 1. Add to PATH (Optional)

To use the tools from anywhere:

**Linux/macOS:**
```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$PATH:/path/to/ec4x_nim/bin"
```

**Windows:**
Add the `bin` directory to your system PATH through System Properties.

### 2. Create Configuration Template

```bash
# Copy configuration template
cp game_config.toml.template my_game_config.toml

# Edit as needed
nano my_game_config.toml
```

## Quick Start

### 1. Create Your First Game

```bash
# Create a new game directory
mkdir my_first_game
cd my_first_game

# Initialize the game
../bin/moderator new .

# Check game statistics
../bin/moderator stats .
```

### 2. Try the Client

```bash
# Create an offline test game
./bin/client offline --players=4 --output-dir=test_game

# View the created game
ls test_game/
```

## Troubleshooting

### Common Issues

#### "nim: command not found"
- Ensure Nim is installed and in your PATH
- Try reinstalling Nim using choosenim
- Restart your terminal after installation

#### "nimble: command not found"
- Nimble should come with Nim
- Try reinstalling Nim
- Check if nimble is in your PATH

#### Compilation Errors
- Ensure you have Nim 2.0.0 or higher: `nim --version`
- Update dependencies: `nimble install -d`
- Clean build artifacts: `make clean` or `rm -rf nimcache bin`

#### Missing Dependencies
```bash
# Reinstall all dependencies
nimble install -d

# Or install specific packages
nimble install cligen toml_serialization
```

#### Permission Errors (Linux/macOS)
```bash
# Make scripts executable
chmod +x build.sh
chmod +x bin/moderator
chmod +x bin/client
```

### Performance Issues

#### Slow Compilation
```bash
# Use faster compilation for development
nim c -d:debug src/moderator.nim

# Use release mode for production
nim c -d:release --opt:speed src/moderator.nim
```

#### Memory Issues
```bash
# Increase GC settings for large games
nim c -d:release --gc:orc src/moderator.nim
```

## Development Setup

### IDE Configuration

#### VS Code
1. Install "Nim" extension
2. Configure workspace settings:
```json
{
    "nim.project": ["src/ec4x_core.nim"],
    "nim.check": true,
    "nim.suggest": true
}
```

#### Vim/Neovim
1. Install nim.vim plugin
2. Add to your vimrc:
```vim
" Nim configuration
autocmd FileType nim setlocal shiftwidth=2 softtabstop=2 expandtab
```

### Testing Setup

```bash
# Run all tests
nimble test

# Run specific test suites
nimble testCore           # Core functionality tests
nimble testStarmap        # Starmap tests
nimble testValidation     # Game specification validation tests

# Run tests with warnings enabled
nimble testWarnings

# Run individual test files directly
nim c -r tests/test_core.nim
nim c -r tests/test_starmap_robust.nim
nim c -r tests/test_starmap_validation.nim
```

### Development Build

```bash
# Build with debug information
make debug

# Or manually
nim c -d:debug --debuginfo --linedir:on src/moderator.nim
```

## Updating

### From Git
```bash
git pull origin main
nimble install -d
make clean
make all
```

### Checking for Updates
```bash
# Check Nim version
nim --version

# Check package versions
nimble list -i
```

## Uninstallation

```bash
# Remove binaries
rm -rf bin/

# Remove build artifacts
make clean

# Remove the entire directory
cd ..
rm -rf ec4x_nim/
```

## Getting Help

### Documentation
- Run `./bin/moderator help` for moderator commands
- Run `./bin/client help` for client commands
- Check the README.md for game rules and features
- Read IMPLEMENTATION_SUMMARY.md for technical details
- See documentation for implementation details

### Community Support
- GitHub Issues: https://github.com/greenm01/ec4x/issues
- Original Project: https://github.com/greenm01/ec4x
- Nim Language: https://nim-lang.org/

### Log Files
- Game logs are stored in game directories
- Debug information available with `-d:debug` builds
- Use `--verbosity:2` for more detailed output

## Next Steps

1. Read the [README.md](README.md) for game rules and features
2. Run the comprehensive test suite to verify installation
3. Create your first game using the moderator tools
4. Explore the technical documentation in the docs/ directory
5. Join a multiplayer game or create your own
6. Contribute to the project on GitHub

Happy gaming!