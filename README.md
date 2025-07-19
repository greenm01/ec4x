# EC4X - Nim Implementation

EC4X is an asynchronous turn-based 4X (eXplore, eXpand, eXploit, eXterminate) wargame for multiple players, featuring a robust Nim implementation with comprehensive starmap generation and pathfinding.

## Overview

Inspired by Esterian Conquest and other classic 4X games, EC4X features:

- **Asynchronous Turn-Based Gameplay**: Turns cycle every 24 hours in real-time
- **Robust Hexagonal Star Map**: Navigate through interconnected star systems via jump lanes
- **Multiple Victory Conditions**: Earn Prestige by crushing rivals and dominating space
- **Scalable Player Count**: Support for 2-12 players with optimized algorithms
- **Game Rule Compliance**: Strict adherence to EC4X game specifications
- **Performance Optimized**: Fast starmap generation (<5ms for largest maps)
- **Comprehensive Testing**: 58 tests covering all edge cases and game rules

## Project Structure

```
ec4x_nim/
├── src/
│   ├── ec4x_core/          # Core game library
│   │   ├── hex.nim         # Hexagonal coordinate system
│   │   ├── ship.nim        # Ship types and capabilities
│   │   ├── system.nim      # Star system representation
│   │   ├── fleet.nim       # Fleet management
│   │   └── starmap.nim     # Star map generation and pathfinding
│   ├── ec4x_core.nim       # Main core module
│   ├── moderator.nim       # Game moderator CLI tool
│   └── client.nim          # Player client CLI tool
├── tests/
│   ├── test_core.nim                 # Core functionality tests
│   ├── test_robust_starmap.nim       # Comprehensive starmap tests
│   └── test_starmap_validation.nim   # Game specification validation
├── docs/                             # Technical documentation
│   ├── IMPLEMENTATION_SUMMARY.md    # Complete implementation summary
│   ├── STARMAP_ANALYSIS.md          # Technical analysis
│   └── STARMAP_ALGORITHM.md         # Algorithm documentation
├── ec4x.nimble                       # Package configuration
└── README.md                         # This file
```

## Features

### Core Game Components

- **Robust Hexagonal Grid System**: Efficient coordinate system with comprehensive validation
- **Ship Types**: Military vessels for combat, Spacelift ships for transport
- **Jump Lanes**: Three types of connections between systems:
  - **Major**: Easy traversal (weight 1) - 2 jumps per turn if you own the path
  - **Minor**: Moderate difficulty (weight 2) - 1 jump per turn
  - **Restricted**: Limited access (weight 3) - excludes crippled/spacelift ships
- **Game-Compliant Star Map Generation**: Follows EC4X specifications exactly
  - Hub has exactly 6 Major lanes to first ring
  - Player systems have exactly 3 lanes each
  - Strategic player placement with distance optimization
- **Advanced Fleet Management**: Fleet composition affects lane traversal capabilities
- **A* Pathfinding**: Efficient pathfinding with fleet restriction compliance

### Moderator Tools

- **Game Creation**: Initialize new games with configurable parameters
- **Server Management**: Start and manage game servers (planned)
- **Turn Processing**: Handle turn maintenance and validation (planned)
- **Game Statistics**: Display comprehensive game information

### Client Interface

- **Game Joining**: Connect to multiplayer games
- **Turn Submission**: Submit player actions
- **Results Retrieval**: Get turn results and game updates
- **Offline Mode**: Create single-player games for testing

## Installation

### Prerequisites

- Nim 2.0.0 or higher
- Nimble package manager

### Dependencies

```bash
nimble install cligen
nimble install toml_serialization
```

### Building

```bash
# Clone the repository
git clone https://github.com/greenm01/ec4x
cd ec4x_nim

# Install dependencies
nimble install -d

# Build the applications
nimble build
```

## Usage

### Creating a New Game

```bash
# Create a new game in the "my_game" directory
./moderator new my_game

# The game will be initialized with default settings
# Edit game_config.toml to customize parameters
```

### Game Configuration

Edit `game_config.toml` in your game directory:

```toml
hostName = "EC4X Host"
gameName = "My EC4X Game"
serverIp = "127.0.0.1"
port = "8080"
numEmpires = 4
```

### Running the Moderator

```bash
# Display game statistics
./moderator stats my_game

# Start the game server (planned)
./moderator start my_game

# Run turn maintenance (planned)
./moderator maint my_game
```

### Using the Client

```bash
# Create an offline game for testing
./client offline --players=4 --output-dir=test_game

# Join a multiplayer game (planned)
./client join --host=game.server.com --port=8080 --player=PlayerName

# Submit a turn file (planned)
./client submit --player=PlayerName --turn-file=my_turn.txt
```

## Development

### Running Tests

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

### Code Structure

The codebase is organized into several key modules:

- **`hex.nim`**: Implements axial coordinate system for hexagonal grids
- **`ship.nim`**: Defines ship types and their capabilities
- **`system.nim`**: Represents star systems with ownership and properties
- **`fleet.nim`**: Manages collections of ships with movement rules
- **`starmap.nim`**: Robust map generation, pathfinding, and connectivity validation
- **`types.nim`**: Core game types and enumerations

### Key Design Decisions

1. **Hexagonal Coordinates**: Uses axial (q,r) coordinates for efficient hex grid operations
2. **Robust Error Handling**: Structured error types with meaningful messages
3. **Game Rule Compliance**: Strict adherence to EC4X game specifications
4. **Performance Focus**: Optimized algorithms without premature complexity
5. **Comprehensive Testing**: 58 tests covering all edge cases and game rules
6. **Type Safety**: Leverages Nim's strong type system to prevent common game logic errors
7. **Modular Architecture**: Clean separation between game logic, tools, and interfaces

## Game Rules

### Victory Conditions

- **Prestige Points**: Earn prestige through territorial control and successful actions
- **Time Limit**: Games have a defined end date (configurable)
- **Elimination**: Last player standing wins (if applicable)

### Turn Structure

1. **Planning Phase**: Players submit orders for their fleets and systems
2. **Resolution Phase**: Server processes all orders simultaneously
3. **Results Phase**: Players receive turn results and updated game state

### Ship Movement

- Ships move through jump lanes between star systems
- Fleet composition determines which lanes can be traversed
- Major lanes allow 2 jumps per turn if you own all systems along the path
- Minor and Restricted lanes allow 1 jump per turn regardless of ownership
- Military ships can use restricted lanes when not crippled
- Spacelift ships provide transport capability but cannot use restricted lanes
- Crippled ships of any type cannot use restricted lanes

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

### Development Tools

- **Nim**: Primary language
- **Nimble**: Build tool and package manager
- **cligen**: Command-line argument parsing
- **toml_serialization**: Configuration file handling

### Development Commands

```bash
# Build binaries
nimble build              # Release build
nimble buildDebug         # Debug build

# Check syntax
nimble check              # Check all source files

# Clean build artifacts
nimble clean

# Generate documentation
nimble docs

# Run examples
nimble example            # Run example commands
nimble demo              # Build and run demo
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Original Project

This is a robust Nim implementation of the EC4X project by Mason Austin Green, featuring comprehensive starmap generation, error handling, and strict game rule compliance.
Original repository: https://github.com/greenm01/ec4x

## Technical Achievements

- ✅ **Robust Starmap Implementation**: Comprehensive and reliable starmap generation
- ✅ **Game Rule Compliance**: Strict adherence to EC4X specifications
- ✅ **Comprehensive Testing**: 58 tests covering all edge cases
- ✅ **Performance Optimization**: <5ms generation for largest maps
- ✅ **Error Handling**: Graceful handling of all edge cases (2-12 players)
- ✅ **Specification Compliance**: Full compliance with EC4X game specification

## Future Plans

- [ ] Network multiplayer support
- [ ] Web-based client interface
- [ ] Advanced AI opponents
- [ ] Campaign mode with persistent universes
- [ ] Real-time notifications and messaging
- [ ] Spectator mode and replay system

## Contact

For questions, suggestions, or contributions, please open an issue on GitHub or contact the maintainers.