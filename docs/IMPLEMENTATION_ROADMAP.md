# EC4X Implementation Roadmap

## Development Strategy

**Offline First, Network Later:** Build complete gameplay systems for local/hotseat multiplayer before adding Nostr integration. This approach:
- Validates game mechanics independently of network complexity
- Enables rapid iteration and testing
- Separates concerns (game logic vs transport layer)
- Provides playable game at each milestone

**Implementation order:**
1. **Phase 1**: Complete game engine → Playable offline/localhost
2. **Phase 2**: Add Nostr protocol → Wrap working game in network transport
3. **Phase 3**: Build daemon → Automated turn processing
4. **Phase 4**: Polish TUI → Improved player experience

## Current Status

**Combat System Complete (M4):** Space combat, ground combat, and starbase integration fully implemented and tested with 10,000+ passing tests. Foundation complete. Currently implementing M5 (Economy & Production).

**See `docs/IMPLEMENTATION_PROGRESS.md` for detailed current status.**

---

## Completed Components

### Production-Ready

**Core Engine:**
- Starmap generation (`src/engine/starmap.nim`) - Hex grid, lane generation, pathfinding
- Coordinate system (`src/common/hex.nim`) - Distance calculation, neighbor queries
- Game state types (`src/engine/gamestate.nim`) - Complete data structures
- Turn resolution framework (`src/engine/resolve.nim`) - 4-phase structure
- Order system (`src/engine/orders.nim`) - 16 order types, validation
- Test suite (58 tests, 100% passing)

**Combat System:**
- Complete 3-phase space combat (`src/engine/combat/` - 9 modules)
- Ground combat (bombardment, invasion, blitz)
- Starbase integration (detection, guard mechanics)
- 10,000+ tests passing (stress tested, balance verified)
- Performance: 15,600 combats/second

**Infrastructure:**
- Build system (Nimble with 12 tasks)
- Nix development environment
- Modular test organization (unit, combat, integration, scenarios, fixtures)
- Complete documentation (2,400+ lines)

### Implementation-Ready

**Nostr Transport:**
- Type definitions (`src/transport/nostr/types.nim`)
- Function signatures (`src/transport/nostr/crypto.nim`, `client.nim`, `events.nim`)
- Event schema documented (`docs/EC4X-Nostr-Events.md`)

**Daemon:**
- Module structure (`src/daemon/`)
- Subscriber, processor, publisher, scheduler skeletons

---

## Implementation Phases

### Phase 1: Core Gameplay Systems (4-6 weeks) - IN PROGRESS

**Combat Resolution** ✅ **COMPLETE** (M4)

*Location:* `src/engine/combat/` (9 modules)

Implemented:
- ✅ 3-phase combat resolution (Ambush, Intercept, Main Engagement)
- ✅ CER system with 1d10 rolls and effectiveness multipliers
- ✅ Target priority and diplomatic filtering
- ✅ Damage application with destruction protection
- ✅ Retreat mechanics with ROE and morale
- ✅ Desperation rounds (prevents infinite loops)
- ✅ Multi-faction combat (up to 12 houses)
- ✅ Ground combat (bombardment, invasion, blitz)
- ✅ Starbase integration (detection bonuses, guard orders)

Test Coverage:
- ✅ 10,000+ stress tests (0 spec violations)
- ✅ 10 integrated space combat scenarios
- ✅ 5 ground combat scenarios
- ✅ Tech balance verification
- ✅ Asymmetric warfare scenarios

**Movement & Pathfinding Integration**

*Location:* `src/engine/resolve.nim` (update existing stubs)

Required implementations:
```nim
proc resolveMovementOrder(state: var GameState, houseId: HouseId,
                         order: FleetOrder, events: var seq[GameEvent])
  # Call findPath() from starmap.nim
  # Apply lane traversal rules (1-2 lanes per turn)
  # Handle multi-turn journeys
  # Update fleet location
  # Check for fleet encounters
```

**Economy & Production**

*Location:* `src/engine/economy.nim`

Required implementations:
```nim
proc calculateProduction(colony: Colony, techLevel: int): ProductionOutput
  # Base production from population and infrastructure
  # Apply tech and building modifiers
  # Account for resource quality

proc constructShip(colony: var Colony, shipType: ShipType,
                   treasury: var int): ConstructionResult
  # Validate production capacity and funds
  # Start or advance construction
  # Complete and deploy ship

proc advanceConstruction(colony: var Colony): Option[CompletedProject]
  # Progress all active construction projects
  # Complete finished projects
  # Return completed items

proc applyResearch(house: var House, field: TechField,
                   points: int): ResearchProgress
  # Apply research points to tech tree
  # Check for tech level advancement
  # Update house tech levels
```

**Build Order Processing**

*Location:* `src/engine/resolve.nim` (implement stub)

```nim
proc resolveBuildOrders(state: var GameState, packet: OrderPacket,
                       events: var seq[GameEvent])
  # Validate build orders against production capacity
  # Deduct costs from treasury
  # Queue construction projects
  # Handle infrastructure upgrades
```

### Phase 2: Nostr Protocol Implementation (3-4 weeks)

**Cryptographic Operations**

*Location:* `src/transport/nostr/crypto.nim`

Dependencies:
```nim
requires "nimcrypto >= 0.6.0"
```

Required implementations:
```nim
proc generateKeyPair(): KeyPair
  # Generate secp256k1 keypair
  # Return private and public keys

proc signEvent(event: var NostrEvent, privateKey: array[32, byte])
  # Serialize event to canonical JSON
  # Compute SHA256 hash as event ID
  # Sign with secp256k1

proc verifyEvent(event: NostrEvent): bool
  # Verify event ID matches content
  # Verify signature against pubkey

proc encryptNIP44(plaintext: string, senderPrivKey, recipientPubKey: array[32, byte]): string
  # ECDH for shared secret
  # HKDF key derivation
  # ChaCha20-Poly1305 encryption
  # Base64 encoding

proc decryptNIP44(ciphertext: string, recipientPrivKey, senderPubKey: array[32, byte]): string
  # Base64 decode
  # ECDH for shared secret
  # HKDF key derivation
  # ChaCha20-Poly1305 decryption
```

**WebSocket Relay Client**

*Location:* `src/transport/nostr/client.nim`

Dependencies:
```nim
requires "websocket >= 0.5.0"
```

Required implementations:
```nim
proc connect(client: NostrClient) {.async.}
  # Establish WebSocket connections to all relays
  # Handle connection failures gracefully
  # Store active connections

proc disconnect(client: NostrClient) {.async.}
  # Close all WebSocket connections
  # Clean up resources

proc subscribe(client: NostrClient, subId: string, filters: seq[NostrFilter]) {.async.}
  # Format REQ message per NIP-01
  # Send to all connected relays
  # Track active subscriptions

proc publish(client: NostrClient, event: NostrEvent): Future[bool] {.async.}
  # Format EVENT message
  # Send to all relays
  # Return success if any relay accepts

proc listen(client: NostrClient) {.async.}
  # Main event loop
  # Receive messages from relays
  # Parse EVENT, OK, EOSE, CLOSED, NOTICE
  # Dispatch to callbacks
```

**Event Builders**

*Location:* `src/transport/nostr/events.nim`

Required implementations:
```nim
proc createOrderPacket(gameId: string, house: string, turnNum: int,
                      orderJson: string, moderatorPubkey: string,
                      playerKeys: KeyPair): NostrEvent
  # Encrypt order to moderator pubkey
  # Create kind 30001 event with proper tags
  # Sign event

proc createGameState(gameId: string, house: string, turnNum: int,
                    stateJson: string, playerPubkey: string,
                    moderatorKeys: KeyPair): NostrEvent
  # Encrypt state to player pubkey
  # Create kind 30002 event
  # Sign with moderator key

proc createTurnComplete(gameId: string, turnNum: int,
                       summaryJson: string,
                       moderatorKeys: KeyPair): NostrEvent
  # Create public kind 30003 event
  # Include turn summary (unencrypted)
  # Sign with moderator key
```

### Phase 3: Daemon Implementation (2-3 weeks)

**Order Subscriber**

*Location:* `src/daemon/subscriber.nim`

Required implementations:
```nim
proc subscribeToGame(sub: Subscriber, gameId: string, currentTurn: int) {.async.}
  # Create filter for game orders
  # Subscribe to order events (kind 30001)
  # Set up event callback

proc start(sub: Subscriber) {.async.}
  # Connect to relays
  # Subscribe to active games
  # Listen for order events
  # Collect orders until deadline
```

**Order Processor**

*Location:* `src/daemon/processor.nim`

Required implementations:
```nim
proc decryptOrder(proc: Processor, event: NostrEvent): OrderPacket
  # Decrypt NIP-44 content
  # Parse JSON order data
  # Validate schema

proc validateOrder(proc: Processor, order: OrderPacket): bool
  # Check turn number matches
  # Validate fleet orders
  # Verify build orders against resources

proc resolveTurn(proc: Processor, gameId: string, orders: seq[OrderPacket]): JsonNode
  # Load game state
  # Call engine.resolveTurn()
  # Generate per-player filtered views
  # Return new state and events
```

**State Publisher**

*Location:* `src/daemon/publisher.nim`

Required implementations:
```nim
proc publishGameState(pub: Publisher, gameId: string, house: string,
                     turnNum: int, stateJson: JsonNode,
                     playerPubkey: string) {.async.}
  # Encrypt state to player pubkey
  # Create kind 30002 event
  # Publish to all relays

proc publishTurnComplete(pub: Publisher, gameId: string, turnNum: int,
                        summaryJson: JsonNode) {.async.}
  # Create kind 30003 event (public)
  # Include leaderboard, major events
  # Publish to all relays

proc publishSpectatorFeed(pub: Publisher, gameId: string, turnNum: int,
                         feedJson: JsonNode) {.async.}
  # Create kind 30006 event (sanitized view)
  # Publish public spectator data
```

**Turn Scheduler**

*Location:* `src/daemon/scheduler.nim`

Required implementations:
```nim
proc timeUntilNextTurn(sched: Scheduler): Duration
  # Calculate time until configured turn time
  # Account for timezone
  # Return duration

proc start(sched: Scheduler) {.async.}
  # Main scheduling loop
  # Sleep until turn deadline
  # Call onTurnTrigger callback
  # Repeat
```

**Daemon Integration**

*Location:* `src/main/daemon.nim`

Required implementations:
```nim
proc loadConfig(path: string): DaemonConfig
  # Parse TOML configuration
  # Validate relay URLs
  # Load moderator key path

proc loadModeratorKey(path: string): array[32, byte]
  # Read private key from secure file
  # Decode hex or base64
  # Return key bytes

proc main() {.async.}
  # Load configuration
  # Initialize subscriber, processor, publisher
  # Configure scheduler
  # Wire up callbacks
  # Start event loop
  # Handle graceful shutdown
```

### Phase 4: Desktop Client (2-3 weeks)

**Terminal UI**

*Location:* `src/ui/tui.nim` (new)

Consider libraries:
- `illwill` - Low-level terminal control
- `nimwave` - Higher-level TUI framework
- Custom ANSI codes - Fits BBS aesthetic

Required implementations:
```nim
proc displayGameState(state: GameState, house: HouseId)
  # Clear screen
  # Render ASCII hex map
  # Show colony details
  # Display fleet locations
  # Show resources, prestige, tech levels
  # Display turn deadline

proc displayMap(starMap: StarMap, colonies: Table[SystemId, Colony],
               fleets: seq[Fleet], focusSystem: Option[SystemId])
  # ASCII art hex grid
  # Mark player systems
  # Show fleet positions
  # Highlight focus system

proc collectOrders(): OrderPacket
  # Interactive menu system
  # "1. Fleet Orders"
  # "2. Build Orders"
  # "3. Research Allocation"
  # "4. Diplomacy"
  # "5. Submit Turn"
  # Validate inputs
  # Return order packet

proc displayTurnResults(results: TurnResult, events: seq[GameEvent],
                       combatReports: seq[CombatReport])
  # Show turn summary
  # Display battle results
  # Show production updates
  # Highlight major events
```

**Client Network Integration**

*Location:* `src/main/client.nim` (update existing)

Required implementations:
```nim
proc connectToGame(gameId: string, playerKeys: KeyPair, relays: seq[string])
  # Connect to Nostr relays
  # Subscribe to game state events for this player
  # Set up event handlers

proc submitOrders(orders: OrderPacket, gameId: string, moderatorPubkey: string,
                 playerKeys: KeyPair)
  # Create order packet event
  # Encrypt to moderator
  # Publish to relays
  # Confirm submission

proc waitForTurnResults(gameId: string, turnNum: int): GameState
  # Subscribe to turn complete events
  # Wait for kind 30003 for this turn
  # Fetch encrypted state (kind 30002)
  # Decrypt and return
```

---

## Testing Requirements

### Unit Tests

**Combat System:**
```nim
# tests/test_combat.nim
- Damage calculation with various fleet compositions
- Tech modifier application
- Ship destruction and crippling
- Multi-fleet battles
- Edge cases (empty fleets, all crippled)
```

**Economy System:**
```nim
# tests/test_economy.nim
- Production calculation
- Ship construction validation
- Building construction
- Research point application
- Treasury management
```

**Turn Resolution:**
```nim
# tests/test_turn_resolution.nim
- Complete turn cycle with all order types
- Multi-turn game progression
- Victory condition checking
- Player elimination
```

### Integration Tests

**Nostr Protocol:**
```nim
# tests/test_nostr_integration.nim
- Event signing and verification
- Encryption/decryption round-trip
- Relay connection and subscription
- Event publishing and retrieval
```

**Daemon Operations:**
```nim
# tests/test_daemon_integration.nim
- Order collection from relays
- Turn resolution trigger
- State publication to players
- Scheduler timing
```

### Manual Testing

- Create and play complete offline games
- Test Nostr client with public relays
- Run daemon against test games
- Verify TUI usability

---

## Development Workflow

### Build Commands

```bash
nix develop                           # Enter development environment
nimble build                          # Build all binaries
nimble test                          # Run test suite
nimble clean                         # Clean artifacts

nim c -r tests/test_combat.nim       # Run specific test
nim c -d:debug src/main/daemon.nim   # Debug build
```

### Testing Against Relays

```bash
# Public test relays
wss://relay.damus.io
wss://nos.lol
wss://relay.nostr.band

# Test WebSocket connection
websocat wss://relay.damus.io

# Monitor relay traffic
wscat -c wss://relay.damus.io
```

### Key Management

```bash
# Generate moderator keypair
./bin/moderator keygen --output keys/moderator.key

# Secure key file
chmod 600 keys/moderator.key

# Never commit keys to git
echo "keys/" >> .gitignore
```

---

## Milestones

**Offline Development (Localhost/Hotseat):**
- ✅ **M1**: Starmap generation and pathfinding
- ✅ **M2**: Game state types and turn framework
- ✅ **M3**: Order system and validation
- ✅ **M4**: Combat system complete (space, ground, starbase)
- 🎯 **M5**: Economy and production working
- 🎯 **M6**: Complete offline game to victory (hotseat multiplayer)
- 🎯 **M7**: Basic TUI for order entry

**Network Integration (Nostr Protocol):**
- 🎯 **M8**: Nostr event signing and encryption working
- 🎯 **M9**: Daemon processes turns from relay
- 🎯 **M10**: Two players complete turn via Nostr
- 🎯 **M11**: Complete game to victory over Nostr
- 🎯 **M12**: Production deployment on VPS
- 🎯 **M13**: Multi-player game with 4+ players

---

## References

### Technical Documentation

- **Nim Language**: https://nim-lang.org/docs/
- **Nim Async I/O**: https://nim-lang.org/docs/asyncdispatch.html
- **NIP-01 (Nostr Protocol)**: https://github.com/nostr-protocol/nips/blob/master/01.md
- **NIP-44 (Encryption)**: https://github.com/nostr-protocol/nips/blob/master/44.md

### Project Documentation

- `docs/EC4X-Architecture.md` - System architecture
- `docs/EC4X-Nostr-Events.md` - Event schema reference
- `docs/EC4X-VPS-Deployment.md` - Deployment procedures
- `docs/specs/` - Game rules and mechanics

### Dependencies

- **nimcrypto**: https://github.com/cheatfate/nimcrypto
- **websocket**: https://github.com/niv/websocket.nim
- **toml_serialization**: https://github.com/status-im/nim-toml-serialization

---

## Notes

**Implementation Order:** Gameplay systems first, then Nostr integration. This allows offline testing and iteration before adding network complexity.

**Testing Strategy:** Write tests as you implement. Every new procedure should have corresponding test cases.

**Commit Discipline:** Small, focused commits. Each commit should compile and pass existing tests.

**Code Quality:** Prioritize clarity over cleverness. The codebase should be maintainable and extensible.

---

*Foundation complete. Implementation ready to proceed.*
