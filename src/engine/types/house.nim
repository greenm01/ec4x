import std/[tables, options]
import ./[core, tech, espionage, income, player_state]

type
  HouseStatus* {.pure.} = enum
    Active
    Autopilot
    DefensiveCollapse

  House* = object
    id*: HouseId
    name*: string
    prestige*: int32
    treasury*: int32
    techTree*: TechTree
    espionageBudget*: EspionageBudget
    taxPolicy*: TaxPolicy
    intel*: IntelDatabase # Intel database for fog-of-war
    latestIncomeReport*: Option[HouseIncomeReport] # For HackStarbase missions
    isEliminated*: bool
    eliminatedTurn*: int32
    # House status tracking
    status*: HouseStatus
    turnsWithoutOrders*: int32
    consecutiveShortfallTurns*: int32
    negativePrestigeTurns*: int32
    # Maintenance shortfall tracking (house-level economic penalties)
    maintenanceShortfallShips*: Table[ShipId, int32]
    maintenanceShortfallNeorias*: Table[NeoriaId, int32]
    maintenanceShortfallKastras*: Table[KastraId, int32]
    maintenanceShortfallGroundUnits*: Table[GroundUnitId, int32]
    # Special assets
    planetBreakerCount*: int32
    # Nostr/multiplayer fields (persisted in msgpack)
    nostrPubkey*: string # Nostr public key (hex or npub format)
    inviteCode*: string # Human-readable invite code for slot claim

  Houses* = object
    entities*: EntityManager[HouseId, House] # Core storage
