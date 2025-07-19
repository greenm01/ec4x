# TODO: Fleet Orders and Gameplay Implementation

## Overview

This document outlines the complete implementation plan for the EC4X fleet order system based on a **hybrid tabletop/computer game** concept. The game combines physical hex maps with computer-assisted order processing, using a simple but sophisticated text-based interface for fleet management.

## Game Design Concept

### **Hybrid Tabletop/Computer Game**
- **Physical hex maps** - Beautiful vector graphics printed for tabletop use
- **Computer client** - Text-based interface for order entry and fleet management
- **Server processing** - Handles turn resolution and conflict processing
- **90's aesthetic** - Retro feel with modern reliability
- **Desktop-only** - No mobile or web versions

### **Player Workflow**
1. **Study physical map** - Plan strategy on printed hex maps
2. **Enter orders** - Use text client for fleet commands
3. **Submit turn** - Server processes all player orders
4. **Print new maps** - Updated hex maps for next turn
5. **External tools** - Players use Excel/paper for complex planning

## Current Implementation Status

### ✅ **Completed - Basic Foundation**
- [x] Hexagonal grid system with proper mathematics
- [x] Basic A* pathfinding between systems
- [x] Fleet lane traversal restrictions (Major/Minor/Restricted)
- [x] Movement cost calculation
- [x] Game specification compliance (hub lanes, player placement)
- [x] Comprehensive testing (56 tests)

### ❌ **Missing - Core Gameplay Features**
- [ ] Turn-based movement system
- [ ] Fleet order execution framework
- [ ] Player intel/fog of war system
- [ ] Fleet encounter detection and resolution
- [ ] Text-based client interface
- [ ] TCP server for multiplayer
- [ ] Map generation (PDF/SVG export)

## Architecture Overview

### **Technology Stack**
- **Server**: Pure Nim TCP server with JSON protocol
- **Client**: illwill-based terminal interface
- **Database**: SQLite for simplicity
- **Maps**: PDF/SVG vector graphics generation
- **Protocol**: JSON messages over TCP sockets

### **Data-Oriented Design**
- Pure data structures separate from processing logic
- Immutable data where possible
- Pure functions for all game logic
- No object-oriented patterns

## High Priority Implementation Tasks

### 1. TCP Server Foundation

**Issue**: No multiplayer server infrastructure exists.

**Required Components**:
```nim
# Server core
proc startGameServer*(port: int): GameServer
proc handlePlayerConnection*(conn: TcpConnection)
proc processPlayerMessage*(msg: JsonNode, session: PlayerSession)
proc broadcastUpdates*(gameId: GameId, updates: seq[PlayerUpdate])

# Protocol handling
type
  ClientMessage* = object
    msgType*: string  # "login", "submit_order", "get_status"
    playerId*: string
    gameId*: string
    data*: JsonNode

  ServerMessage* = object
    msgType*: string  # "order_result", "turn_update", "error"
    success*: bool
    data*: JsonNode
```

**Priority**: **CRITICAL** - Foundation for all multiplayer features

### 2. illwill Client Interface

**Issue**: No user interface for fleet management exists.

**Required Screens**:
- Fleet overview with filtering/sorting
- Detailed fleet management
- Order entry and batch operations
- Intel reports and system status
- Turn results display

**Example Interface**:
```nim
# Fleet overview screen
┌─────────────────────────────────────────────────────────────────────────────────┐
│ Fleet Command - Turn 045 - Commander Kirk                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│ ID  Name           Location    Ships      Status    Orders      ETA  Last Seen  │
│ ─── ────────────── ─────────── ────────── ───────── ─────────── ──── ────────── │
│ 001 Alpha Strike   Sol-B12     3M,1S      Ready     Hold        0    This Turn  │
│ 002 Beta Patrol    Vega-C15    2M         Moving    Patrol      0    This Turn  │
│ 003 Gamma Scout    Unknown     1Sc        Missing   Explore     ?    Turn 043   │
│                                                                                 │
│ [V]iew [E]dit [C]reate [S]ort [F]ilter [O]rders [Q]uit                          │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Priority**: **CRITICAL** - Primary user interface

### 3. Turn-Based Movement System

**Issue**: Current pathfinding is instantaneous, but game has turn-based rules.

**Game Rules**:
- 2 major lanes per turn if you own all systems along path
- 1 lane per turn otherwise
- 1 lane max when entering enemy/unexplored systems
- Fleet encounters when fleets meet

**Required Functions**:
```nim
proc calculateMovementTurns*(starMap: StarMap, start: SystemId, goal: SystemId,
                           fleet: FleetState, playerSystems: seq[SystemId]): int

proc planMultiTurnRoute*(starMap: StarMap, start: SystemId, goal: SystemId,
                        fleet: FleetState, intel: PlayerIntel): MovementPlan

proc validateRouteOwnership*(starMap: StarMap, path: seq[SystemId],
                           playerId: PlayerId): bool
```

**Priority**: **HIGH** - Core gameplay mechanic

### 4. Fleet Order System

**Issue**: No implementation of the 16 fleet orders from specification.

**Required Orders** (from ec4x_specs.md Section 6.2):
- [ ] 01 - Move Fleet
- [ ] 02 - Seek Home (find closest friendly system)
- [ ] 03 - Patrol a System
- [ ] 04 - Guard a Starbase
- [ ] 05 - Guard/Blockade a Planet
- [ ] 06 - Bombard a Planet
- [ ] 07 - Invade a Planet
- [ ] 08 - Blitz a Planet
- [ ] 09 - Spy on a Planet
- [ ] 10 - Hack a Starbase
- [ ] 11 - Spy on a System
- [ ] 12 - Colonize a Planet
- [ ] 13 - Join another Fleet
- [ ] 14 - Rendezvous at System
- [ ] 15 - Salvage

**Priority**: **HIGH** - Core gameplay features

### 5. Player Intel System

**Issue**: No fog of war or limited intelligence system.

**Required Features**:
- Players only know what they've discovered
- Fleet sightings with confidence levels
- System exploration and mapping
- Intelligence reports and analysis

**Required Functions**:
```nim
proc updatePlayerIntel*(playerId: PlayerId, sightings: seq[FleetSighting])
proc getVisibleSystems*(playerId: PlayerId, gameState: GameState): seq[SystemId]
proc estimateEnemyPositions*(intel: PlayerIntel, currentTurn: TurnNumber): seq[SystemId]
proc generateIntelReport*(playerId: PlayerId, gameState: GameState): IntelReport
```

**Priority**: **HIGH** - Critical for multiplayer balance

## Detailed Implementation Plan

### Module Structure

```nim
src/ec4x_core/
├── fleet_orders/
│   ├── types.nim           # Data structures and enums
│   ├── validation.nim      # Order validation logic
│   ├── movement.nim        # Turn-based movement algorithms
│   ├── pathfinding.nim     # Enhanced pathfinding with intel
│   ├── resolution.nim      # Order execution and conflict resolution
│   └── encounters.nim      # Fleet encounter handling
├── game_state/
│   ├── player_intel.nim    # Player knowledge/fog of war
│   ├── fleet_tracking.nim  # Fleet position and status
│   ├── system_control.nim  # System ownership tracking
│   └── turn_processing.nim # Server-side turn resolution
├── database/
│   ├── player_db.nim       # Individual player database
│   ├── server_db.nim       # Authoritative server database
│   └── sync.nim            # Database synchronization
├── networking/
│   ├── server.nim          # TCP server implementation
│   ├── protocol.nim        # JSON message protocol
│   └── session.nim         # Player session management
├── ui/
│   ├── terminal.nim        # illwill interface foundation
│   ├── fleet_screens.nim   # Fleet management screens
│   ├── intel_screens.nim   # Intelligence and reports
│   └── order_entry.nim     # Order input and validation
└── map_export/
    ├── pdf_generator.nim   # PDF hex map generation
    ├── svg_generator.nim   # SVG vector graphics
    └── print_layouts.nim   # Print-optimized layouts
```

### Core Data Structures

```nim
# types.nim - Pure data structures
type
  FleetId* = distinct uint32
  PlayerId* = distinct uint32
  SystemId* = distinct uint32
  TurnNumber* = distinct uint32

  # Fleet order data
  FleetOrder* = object
    id*: FleetId
    playerId*: PlayerId
    orderType*: FleetOrderType
    targetSystem*: SystemId
    targetFleet*: FleetId
    submittedTurn*: TurnNumber
    parameters*: seq[OrderParameter]

  FleetOrderType* = enum
    HoldPosition, MoveFleet, SeekHome, PatrolSystem,
    GuardStarbase, GuardPlanet, BombardPlanet, InvadePlanet,
    BlitzPlanet, SpyPlanet, HackStarbase, SpySystem,
    ColonizePlanet, JoinFleet, RendezvousSystem, Salvage

  # Fleet state data
  FleetState* = object
    id*: FleetId
    playerId*: PlayerId
    currentSystem*: SystemId
    ships*: seq[Ship]
    status*: FleetStatus
    currentOrder*: FleetOrder
    lastUpdated*: TurnNumber

  FleetStatus* = enum
    Ready, Moving, InCombat, Damaged, Missing, Destroyed

  # Movement planning data
  MovementPlan* = object
    fleetId*: FleetId
    route*: seq[SystemId]
    turnsPerHop*: seq[uint8]
    totalTurns*: uint32
    ownershipValidated*: bool
    riskAssessment*: float32

  # Player intel data (what player knows)
  PlayerIntel* = object
    playerId*: PlayerId
    knownSystems*: seq[SystemId]
    knownFleets*: seq[FleetSighting]
    systemControl*: Table[SystemId, PlayerId]
    lastUpdated*: TurnNumber

  FleetSighting* = object
    fleetId*: FleetId
    systemId*: SystemId
    shipCount*: uint32
    fleetType*: FleetType
    lastSeen*: TurnNumber
    confidence*: float32  # 0.0-1.0

  # Fleet encounter data
  FleetEncounter* = object
    turn*: TurnNumber
    system*: SystemId
    fleets*: seq[FleetId]
    encounterType*: EncounterType
    resolved*: bool

  EncounterType* = enum
    Peaceful, Standoff, Combat, Pursuit
```

### Processing Functions (Pure Functions)

```nim
# movement.nim - Movement calculation algorithms
proc calculateMovementTurns*(route: seq[SystemId], fleet: FleetState,
                           playerSystems: seq[SystemId]): uint32

proc planTurnBasedRoute*(starMap: StarMap, start: SystemId, goal: SystemId,
                        fleet: FleetState, intel: PlayerIntel): MovementPlan

proc validateMovementLegality*(plan: MovementPlan, starMap: StarMap,
                             gameState: GameState): bool

# pathfinding.nim - Intel-based pathfinding
proc findPathWithIntel*(starMap: StarMap, start: SystemId, goal: SystemId,
                       fleet: FleetState, intel: PlayerIntel): PathResult

proc findClosestFriendlySystem*(starMap: StarMap, start: SystemId,
                               intel: PlayerIntel): SystemId

proc calculateRouteRisk*(route: seq[SystemId], intel: PlayerIntel): float32

# resolution.nim - Server-side order processing
proc resolveFleetOrders*(orders: seq[FleetOrder], gameState: GameState,
                        starMap: StarMap): OrderResolution

proc detectFleetEncounters*(fleetStates: seq[FleetState],
                          movements: seq[MovementPlan]): seq[FleetEncounter]

proc processFleetEncounter*(encounter: FleetEncounter,
                          gameState: GameState): EncounterResult

# validation.nim - Order validation
proc validateFleetOrder*(order: FleetOrder, fleet: FleetState,
                        gameState: GameState): ValidationResult

proc checkOrderPrerequisites*(order: FleetOrder, fleet: FleetState): bool
```

### Network Protocol Design

```nim
# protocol.nim - JSON message protocol
type
  # Client to server messages
  LoginRequest* = object
    username*: string
    password*: string
    gameId*: string

  OrderSubmission* = object
    playerId*: PlayerId
    gameId*: GameId
    orders*: seq[FleetOrder]
    turnNumber*: TurnNumber

  StatusRequest* = object
    playerId*: PlayerId
    gameId*: GameId

  # Server to client messages
  LoginResponse* = object
    success*: bool
    playerId*: PlayerId
    gameState*: PlayerGameState
    message*: string

  OrderResponse* = object
    success*: bool
    acceptedOrders*: seq[FleetId]
    rejectedOrders*: seq[OrderError]

  TurnUpdate* = object
    turnNumber*: TurnNumber
    fleetUpdates*: seq[FleetState]
    systemUpdates*: seq[SystemUpdate]
    encounters*: seq[EncounterReport]
    intelUpdates*: seq[FleetSighting]

  PlayerGameState* = object
    playerId*: PlayerId
    gameId*: GameId
    currentTurn*: TurnNumber
    ownFleets*: seq[FleetState]
    intel*: PlayerIntel
    messages*: seq[GameMessage]
```

### User Interface Screens

```nim
# fleet_screens.nim - Fleet management interface
proc displayFleetOverview*(fleets: seq[FleetState], filters: FleetFilters)
proc displayFleetDetails*(fleet: FleetState, availableOrders: seq[FleetOrderType])
proc displayBatchOrderEntry*(fleets: seq[FleetState])
proc displayFleetFilters*(currentFilters: FleetFilters)

# intel_screens.nim - Intelligence and reports
proc displayIntelReport*(intel: PlayerIntel, encounters: seq[EncounterReport])
proc displaySystemStatus*(systems: seq[SystemStatus])
proc displayEnemyMovements*(sightings: seq[FleetSighting])

# order_entry.nim - Order input and validation
proc enterFleetOrder*(fleet: FleetState): FleetOrder
proc validateOrderInput*(order: FleetOrder, fleet: FleetState): ValidationResult
proc displayOrderConfirmation*(orders: seq[FleetOrder])
```

## Implementation Timeline

### Phase 1: Core Infrastructure (6-8 weeks)
- [ ] TCP server foundation with JSON protocol
- [ ] Basic illwill client interface
- [ ] Player session management
- [ ] Database schema and basic operations
- [ ] Simple order submission and validation

### Phase 2: Movement System (4-6 weeks)
- [ ] Turn-based movement calculation
- [ ] Route ownership validation
- [ ] Multi-turn route planning
- [ ] Fleet encounter detection
- [ ] Movement rule enforcement

### Phase 3: Fleet Order System (8-10 weeks)
- [ ] Implement orders 01-05 (Move, Seek Home, Patrol, Guard)
- [ ] Implement orders 06-10 (Combat orders, Spy operations)
- [ ] Implement orders 11-15 (Colonize, Join, Rendezvous, Salvage)
- [ ] Order validation and prerequisites
- [ ] Multi-fleet coordination

### Phase 4: Player Intel System (4-6 weeks)
- [ ] Fog of war implementation
- [ ] Fleet sighting system
- [ ] Intelligence report generation
- [ ] System exploration mechanics
- [ ] Enemy position estimation

### Phase 5: Advanced UI Features (6-8 weeks)
- [ ] Advanced fleet filtering and sorting
- [ ] Batch order operations
- [ ] Fleet templates and saved orders
- [ ] Intel analysis tools
- [ ] Turn result presentation

### Phase 6: Map Generation (4-6 weeks)
- [ ] PDF hex map generation
- [ ] SVG vector graphics export
- [ ] Print-optimized layouts
- [ ] Fleet position overlays
- [ ] Player-specific map views

### Phase 7: Polish and Testing (4-6 weeks)
- [ ] Comprehensive testing suite
- [ ] Performance optimization
- [ ] Error handling and recovery
- [ ] Documentation and help system
- [ ] Deployment and distribution

## Testing Strategy

### Unit Tests
- Pure function testing for all game logic
- Movement calculation validation
- Order validation and execution
- Intel system accuracy
- Protocol message handling

### Integration Tests
- Full turn processing simulation
- Multi-player order resolution
- Database synchronization
- Network protocol validation
- UI workflow testing

### Performance Tests
- Large-scale fleet movement simulation
- Concurrent player command processing
- Database query optimization
- Network latency impact analysis
- Memory usage with large games

### User Experience Tests
- Fleet management workflow efficiency
- Order entry speed and accuracy
- Intel report clarity and usefulness
- Map generation quality
- Error message clarity

## Technical Considerations

### Performance Optimization
- **Spatial indexing** for fleet encounter detection
- **Cached pathfinding** for common routes
- **Delta updates** for database synchronization
- **Batch processing** for turn resolution
- **Memory pooling** for frequent allocations

### Error Handling
- **Graceful degradation** for network issues
- **Order validation** at multiple levels
- **Rollback capability** for failed turns
- **Audit logging** for debugging
- **Clear error messages** for players

### Scalability
- **Stateless processing** functions
- **Horizontal scaling** for multiple games
- **Database sharding** for large player counts
- **Load balancing** for high traffic
- **Caching layers** for frequently accessed data

### Security
- **Input validation** for all player commands
- **Authentication** and session management
- **Rate limiting** for order submission
- **Audit trails** for all player actions
- **Data encryption** for sensitive information

## Success Criteria

### Functional Requirements
- All 16 fleet orders implemented and tested
- Turn-based movement follows specification exactly
- Player intel system provides balanced fog of war
- Fleet encounters are detected and resolved correctly
- Maps generate as beautiful vector graphics for printing

### Quality Requirements
- 100% test coverage for core game logic
- <100ms response time for typical operations
- <1s turn processing for games up to 12 players
- Zero data loss during network interruptions
- Clear, intuitive user interface

### User Experience Goals
- Players can manage 20+ fleets efficiently
- Order entry is fast and error-free
- Intel reports provide actionable information
- Maps are suitable for professional tabletop play
- Game feels authentic to classic computer wargames

## Dependencies

### External Libraries
- **illwill** - Terminal user interface
- **asyncdispatch** - Async networking
- **json** - Message protocol
- **sqlite3** - Database storage
- **cairo** or **svg** - Vector graphics generation

### Development Tools
- **Nim compiler** (stable version)
- **Testing framework** (unittest)
- **Documentation generator** (nimdoc)
- **Profiling tools** for performance analysis
- **Version control** (git)

## Deployment Strategy

### Server Deployment
- **Single executable** for easy deployment
- **Systemd service** for Linux servers
- **Config file** for server settings
- **Automated backups** before each turn
- **Log rotation** for maintenance

### Client Distribution
- **Single executable** for each platform
- **Auto-updater** for new versions
- **Config file** for connection settings
- **Offline mode** for order planning
- **Installation packages** for each OS

This comprehensive implementation plan provides the foundation for creating the complete EC4X fleet order system while maintaining the hybrid tabletop/computer game concept and authentic retro aesthetic.

---

**Last Updated**: [Current Date]
**Status**: Planning Phase - Ready for Implementation
**Priority**: High (Core gameplay functionality)
**Estimated Timeline**: 36-50 weeks total development time
