# EC4X KDL Order Format Specification

## Overview

This document specifies the KDL (Cuddly Document Language) format for player
order submission in EC4X. All player commands are serialized as KDL documents
for both human readability and cross-language compatibility.

**Benefits:**
- Human-readable and editable
- Claude/AI agents can generate orders directly
- Cross-language support (Rust, Python, Go, JS, Nim implementations exist)
- Type-safe with annotations
- Consistent format for localhost and Nostr transports

**File naming:** `turn_{N}_house_{H}.kdl` (e.g., `turn_5_house_1.kdl`)

**KDL Version:** 2.0 (uses `#true`, `#false`, `#null` keywords)

---

## Order Lifecycle

```
1. Player/AI generates orders KDL file
2. Submit to daemon:
   - Localhost: Drop file in data/games/{uuid}/orders/
   - Nostr: Encrypt and publish as event
3. Daemon validates entire packet
4. If valid: Store in DB, return success response
5. If invalid: Reject entire packet, return errors
```

**Validation policy:** Reject entire packet on first error. Player must fix
and resubmit. This ensures atomic, consistent order processing.

---

## Root Node

Every order file has a single root `orders` node:

```kdl
orders turn=5 house=(HouseId)1 {
  // All commands nested here
}
```

**Required attributes:**
- `turn` - Turn number these orders apply to
- `house` - House ID (type-annotated)

---

## Type Annotations

KDL type annotations clarify ID types for validation:

| Annotation | Example | Description |
|------------|---------|-------------|
| `(HouseId)` | `(HouseId)1` | House identifier |
| `(FleetId)` | `(FleetId)42` | Fleet identifier |
| `(ShipId)` | `(ShipId)100` | Ship identifier |
| `(ColonyId)` | `(ColonyId)3` | Colony identifier |
| `(SystemId)` | `(SystemId)15` | Star system identifier |
| `(NeoriaId)` | `(NeoriaId)5` | Production facility ID |
| `(KastraId)` | `(KastraId)2` | Defensive facility ID |
| `(GroundUnitId)` | `(GroundUnitId)10` | Ground unit ID |
| `(ProposalId)` | `(ProposalId)7` | Diplomatic proposal ID |

---

## Command Categories

### 1. Zero-Turn Commands

Zero-turn commands execute immediately during order submission, before turn
resolution. Results are returned in the response.

```kdl
orders turn=5 house=(HouseId)1 {
  zero-turn {
    // Fleet reorganization
    detach-ships fleet=(FleetId)1 ships=[0 2 4]
    transfer-ships from=(FleetId)1 to=(FleetId)2 ships=[1 3]
    merge-fleets from=(FleetId)3 into=(FleetId)1
    
    // Cargo operations
    load-cargo fleet=(FleetId)1 type=marines quantity=50
    unload-cargo fleet=(FleetId)2
    
    // Fighter operations
    load-fighters fleet=(FleetId)1 carrier=(ShipId)10 \
                  fighters=[(ShipId)20 (ShipId)21]
    unload-fighters fleet=(FleetId)1 carrier=(ShipId)10
    transfer-fighters from-carrier=(ShipId)10 to-carrier=(ShipId)11 \
                      fighters=[(ShipId)20]
    
    // Status change
    reactivate fleet=(FleetId)5
  }
}
```

**Zero-turn command types:**

| Command | Parameters | Description |
|---------|------------|-------------|
| `detach-ships` | fleet, ships (indices) | Split ships into new fleet |
| `transfer-ships` | from, to, ships (indices) | Move ships between fleets |
| `merge-fleets` | from, into | Merge source into target fleet |
| `load-cargo` | fleet, type, quantity | Load marines/colonists |
| `unload-cargo` | fleet | Unload all cargo |
| `load-fighters` | fleet, carrier, fighters | Load fighters onto carrier |
| `unload-fighters` | fleet, carrier | Unload fighters to colony |
| `transfer-fighters` | from-carrier, to-carrier, fighters | Move fighters |
| `reactivate` | fleet | Return reserve/mothballed to active |

**Cargo types:** `marines`, `colonists`

---

### 2. Fleet Commands

Operational orders for fleets. Each fleet can have one command per turn.

```kdl
orders turn=5 house=(HouseId)1 {
  // Simple commands (no parameters)
  fleet (FleetId)1 hold
  fleet (FleetId)2 patrol
  fleet (FleetId)3 guard-colony
  fleet (FleetId)4 guard-starbase
  fleet (FleetId)5 seek-home
  fleet (FleetId)6 salvage
  fleet (FleetId)7 reserve
  fleet (FleetId)8 mothball
  
  // Commands with target system
  fleet (FleetId)10 {
    move to=(SystemId)15 roe=6
  }
  fleet (FleetId)11 {
    colonize system=(SystemId)23
  }
  fleet (FleetId)12 {
    blockade system=(SystemId)30
  }
  fleet (FleetId)13 {
    bombard system=(SystemId)30
  }
  fleet (FleetId)14 {
    invade system=(SystemId)30
  }
  fleet (FleetId)15 {
    blitz system=(SystemId)30
  }
  fleet (FleetId)16 {
    scout-colony system=(SystemId)40
  }
  fleet (FleetId)17 {
    scout-system system=(SystemId)41
  }
  fleet (FleetId)18 {
    hack-starbase system=(SystemId)42
  }
  fleet (FleetId)19 {
    view system=(SystemId)50
  }
  fleet (FleetId)20 {
    rendezvous at=(SystemId)25
  }
  
  // Commands with target fleet
  fleet (FleetId)21 {
    join-fleet target=(FleetId)10
  }
}
```

**Fleet command types:**

| Command | Parameters | Description |
|---------|------------|-------------|
| `hold` | - | Hold position |
| `move` | to, roe? | Navigate to system |
| `seek-home` | - | Return to nearest friendly colony |
| `patrol` | - | Patrol current system |
| `guard-colony` | - | Defend colony |
| `guard-starbase` | - | Protect starbase |
| `blockade` | system | Siege colony (40% production penalty) |
| `bombard` | system | Orbital bombardment |
| `invade` | system | Ground invasion |
| `blitz` | system | Combined bombard + invade |
| `colonize` | system | Establish colony (requires ETAC) |
| `scout-colony` | system | Spy on colony (scouts consumed) |
| `scout-system` | system | Recon system (scouts consumed) |
| `hack-starbase` | system | Cyber attack on starbase |
| `join-fleet` | target | Merge into another fleet |
| `rendezvous` | at | Meet at system |
| `salvage` | - | Disband for 50% PP |
| `reserve` | - | 50% maintenance, reduced combat |
| `mothball` | - | 0% maintenance, offline |
| `view` | system | Long-range recon |

**Optional parameters:**
- `roe` - Rules of Engagement (0-10), default 6

---

### 3. Build Commands

Construction orders for ships, facilities, ground units, and industrial units.

```kdl
orders turn=5 house=(HouseId)1 {
  build (ColonyId)1 {
    // Ships
    ship corvette
    ship frigate
    ship destroyer quantity=2
    ship light-cruiser
    ship cruiser
    ship battlecruiser
    ship battleship
    ship dreadnought
    ship super-dreadnought
    ship carrier
    ship super-carrier
    ship raider
    ship scout quantity=3
    ship etac
    ship troop-transport
    
    // Facilities
    facility spaceport
    facility shipyard
    facility drydock
    facility starbase
    
    // Ground units
    ground army quantity=5
    ground marine quantity=3
    ground ground-battery quantity=2
    ground planetary-shield
    
    // Industrial units (1 PP = 1 IU)
    industrial units=10
  }
}
```

**Ship classes:** `corvette`, `frigate`, `destroyer`, `light-cruiser`,
`cruiser`, `battlecruiser`, `battleship`, `dreadnought`, `super-dreadnought`,
`carrier`, `super-carrier`, `raider`, `scout`, `etac`, `troop-transport`

**Facility classes:** `spaceport`, `shipyard`, `drydock`, `starbase`

**Ground classes:** `army`, `marine`, `ground-battery`, `planetary-shield`

**Optional parameters:**
- `quantity` - Number to build (default 1)

---

### 4. Repair Commands

Manual repair orders (when colony auto-repair is disabled).

```kdl
orders turn=5 house=(HouseId)1 {
  repair (ColonyId)1 {
    ship (ShipId)42 priority=1
    ship (ShipId)43 priority=2
    starbase (KastraId)1 priority=3
    ground-unit (GroundUnitId)15 priority=4
    facility (NeoriaId)3 priority=5
  }
}
```

**Target types:** `ship`, `starbase`, `ground-unit`, `facility`

**Parameters:**
- Target ID (type-annotated)
- `priority` - Repair order priority (lower = first)

---

### 5. Scrap Commands

Salvage entities for 50% PP recovery.

```kdl
orders turn=5 house=(HouseId)1 {
  scrap (ColonyId)1 {
    ship (ShipId)99
    ground-unit (GroundUnitId)50
    neoria (NeoriaId)3 acknowledge-queue-loss=#true
    kastra (KastraId)2
  }
}
```

**Target types:** `ship`, `ground-unit`, `neoria`, `kastra`

**Parameters:**
- `acknowledge-queue-loss` - Required `#true` if facility has queued projects
  (projects destroyed with no refund)

---

### 6. Research Allocation

R&D investment (PP converted to Research Points).

```kdl
orders turn=5 house=(HouseId)1 {
  research {
    // Core levels
    economic 100    // Economic Level (EL)
    science 50      // Science Level (SL)
    
    // Technology fields
    tech {
      cst 25        // Construction Tech
      wep 50        // Weapons Tech
      ter 0         // Terraforming Tech
      eli 25        // Electronic Intelligence
      clk 0         // Cloaking Tech
      sld 0         // Shield Tech
      cic 10        // Counter-Intelligence
      stl 0         // Strategic Lift Tech
      fc 0          // Flagship Command Tech
      sc 0          // Strategic Command Tech
      fd 0          // Fighter Doctrine
      aco 0         // Advanced Carrier Ops
    }
  }
}
```

**Tech field abbreviations:**

| Abbrev | Full Name | Effect |
|--------|-----------|--------|
| `cst` | Construction Tech | Ship classes, dock capacity |
| `wep` | Weapons Tech | Ship AS/DS (+10%/level) |
| `ter` | Terraforming Tech | Planet upgrades |
| `eli` | Electronic Intelligence | Detection capability |
| `clk` | Cloaking Tech | Raider stealth |
| `sld` | Shield Tech | Planetary shields |
| `cic` | Counter-Intelligence | Espionage defense |
| `stl` | Strategic Lift Tech | Transport capacity |
| `fc` | Flagship Command Tech | Ships per fleet |
| `sc` | Strategic Command Tech | Max fleet count |
| `fd` | Fighter Doctrine | Fighter capacity |
| `aco` | Advanced Carrier Ops | Carrier capacity |

---

### 7. Espionage

EBP/CIP investment and covert operations.

```kdl
orders turn=5 house=(HouseId)1 {
  espionage {
    // Investment (buy points, 40 PP each)
    invest ebp=200 cip=80
    
    // Operations (cost EBP)
    tech-theft target=(HouseId)3
    sabotage-low target=(HouseId)2 system=(SystemId)15
    sabotage-high target=(HouseId)2 system=(SystemId)15
    assassination target=(HouseId)4
    cyber-attack target=(HouseId)3 system=(SystemId)20
    economic-manipulation target=(HouseId)2
    psyops target=(HouseId)4
    counter-intel-sweep
    intel-theft target=(HouseId)3
    plant-disinfo target=(HouseId)2
  }
}
```

**Espionage operations:**

| Operation | EBP Cost | Effect |
|-----------|----------|--------|
| `tech-theft` | 5 | Steal 10 SRP |
| `sabotage-low` | 2 | -1d6 IU |
| `sabotage-high` | 7 | -1d20 IU |
| `assassination` | 10 | -50% SRP gain (1 turn) |
| `cyber-attack` | 6 | Cripple starbase |
| `economic-manipulation` | 6 | Halve NCV (1 turn) |
| `psyops` | 3 | -25% tax revenue (1 turn) |
| `counter-intel-sweep` | 4 | Block enemy intel (1 turn) |
| `intel-theft` | 8 | Steal intel database |
| `plant-disinfo` | 6 | Corrupt intel (2 turns) |

**Limit:** Max 3 operations per target house per turn.

---

### 8. Diplomacy

Diplomatic status changes and proposals.

```kdl
orders turn=5 house=(HouseId)1 {
  diplomacy {
    declare-hostile target=(HouseId)3
    declare-enemy target=(HouseId)4
    set-neutral target=(HouseId)5
    propose-deescalate target=(HouseId)2 to=neutral
    propose-deescalate target=(HouseId)6 to=hostile
    accept-proposal id=(ProposalId)7
    reject-proposal id=(ProposalId)8
  }
}
```

**Diplomatic actions:**

| Action | Parameters | Description |
|--------|------------|-------------|
| `declare-hostile` | target | Set status to Hostile |
| `declare-enemy` | target | Set status to Enemy |
| `set-neutral` | target | Request Neutral status |
| `propose-deescalate` | target, to | Submit de-escalation proposal |
| `accept-proposal` | id | Accept pending proposal |
| `reject-proposal` | id | Reject pending proposal |

**De-escalation targets:** `neutral`, `hostile`

---

### 9. Population Transfer

Move colonists via Space Guild.

```kdl
orders turn=5 house=(HouseId)1 {
  transfer from=(ColonyId)1 to=(ColonyId)2 ptu=50
  transfer from=(ColonyId)3 to=(ColonyId)4 ptu=100
}
```

**Parameters:**
- `from` - Source colony
- `to` - Destination colony
- `ptu` - Population Transfer Units to move

**Cost:** Varies by destination planet class (4-15 PP per PTU)

---

### 10. Terraform

Upgrade planet habitability class.

```kdl
orders turn=5 house=(HouseId)1 {
  terraform colony=(ColonyId)3
}
```

**Upgrade path:** Extreme -> Desolate -> Hostile -> Harsh -> Benign -> Lush -> Eden

**Requires:** Appropriate TER tech level researched.

---

### 11. Colony Management

Colony-level configuration.

```kdl
orders turn=5 house=(HouseId)1 {
  colony (ColonyId)1 {
    tax-rate 60
    auto-repair #true
    auto-load-fighters #true
    auto-load-marines #false
  }
  
  colony (ColonyId)2 {
    tax-rate 40
  }
}
```

**Settings:**

| Setting | Type | Description |
|---------|------|-------------|
| `tax-rate` | 0-100 | Colony tax rate percentage |
| `auto-repair` | bool | Enable automatic repair queuing |
| `auto-load-fighters` | bool | Auto-load fighters to carriers |
| `auto-load-marines` | bool | Auto-load marines to transports |

---

## Response Format

Daemon returns a KDL response for each order submission.

### Success Response

```kdl
response turn=5 house=(HouseId)1 {
  status accepted
  commands-processed 15
  
  // Zero-turn command results
  zero-turn-results {
    detach-ships fleet=(FleetId)1 {
      result success
      new-fleet (FleetId)99
    }
    load-cargo fleet=(FleetId)1 {
      result success
      loaded 50
    }
    merge-fleets from=(FleetId)3 {
      result success
    }
  }
}
```

### Failure Response

```kdl
response turn=5 house=(HouseId)1 {
  status rejected
  
  errors {
    error line=3 "Fleet 99 does not exist"
    error line=7 "Colony 5 is not owned by house 1"
    error line=12 "Insufficient treasury for build orders (need 500, have 300)"
    error line=15 "Invalid ship class: battlewagon"
  }
}
```

**Error attributes:**
- `line` - Line number in order file where error occurred
- String content - Human-readable error message

---

## Complete Example

```kdl
// EC4X Orders - Turn 5, House Atreides
orders turn=5 house=(HouseId)1 {

  // Immediate fleet reorganization
  zero-turn {
    load-cargo fleet=(FleetId)3 type=marines quantity=100
    merge-fleets from=(FleetId)7 into=(FleetId)2
  }

  // Fleet operations
  fleet (FleetId)1 {
    move to=(SystemId)15 roe=7
  }
  fleet (FleetId)2 patrol
  fleet (FleetId)3 {
    invade system=(SystemId)20
  }
  fleet (FleetId)4 guard-colony
  fleet (FleetId)5 {
    colonize system=(SystemId)30
  }

  // Production
  build (ColonyId)1 {
    ship destroyer quantity=2
    ship cruiser
    facility shipyard
    ground marine quantity=5
  }
  build (ColonyId)2 {
    ship etac
    ground army quantity=3
    industrial units=20
  }

  // Research
  research {
    economic 50
    science 30
    tech {
      wep 40
      cst 20
    }
  }

  // Espionage
  espionage {
    invest ebp=120
    tech-theft target=(HouseId)3
    sabotage-low target=(HouseId)2 system=(SystemId)25

  }

  // Diplomacy
  diplomacy {
    declare-hostile target=(HouseId)4
  }

  // Colony settings
  colony (ColonyId)1 {
    tax-rate 50
    auto-repair #true
  }
}
```

---

## Validation Rules

The daemon validates the entire order packet. Any error rejects the packet.

### ID Validation
- All fleet/ship/colony/system IDs must exist
- All entities must be owned by the submitting house
- Fleet commands cannot target fleets in transit

### Resource Validation
- Total PP spending (build + research + espionage + transfers) <= treasury
- EBP spending <= available EBP
- CIP spending <= available CIP

### Command Validation
- Fleet commands: Valid command type, valid targets
- Build orders: Valid classes, colony has required facilities
- Espionage: Max 3 ops per target house per turn
- Terraform: Colony meets TER tech requirements

### Type Validation
- Enums must match valid values (ship classes, commands, etc.)
- Booleans must be `#true` or `#false`
- Numbers must be valid integers

---

## Transport

### Localhost Mode

1. Generate `turn_{N}_house_{H}.kdl`
2. Drop in `data/games/{uuid}/orders/`
3. Daemon detects, validates, processes
4. Response written to `data/games/{uuid}/responses/turn_{N}_house_{H}.kdl`

### Nostr Mode

1. Generate KDL order document
2. Compress (optional, zstd recommended)
3. Encrypt to moderator pubkey (NIP-44)
4. Publish as Nostr event with game tags
5. Daemon receives, decrypts, decompresses, validates
6. Response published as encrypted event to player pubkey

---

**Version:** 1.0
**Last Updated:** 2026-01-10
