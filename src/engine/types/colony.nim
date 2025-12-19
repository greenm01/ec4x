## Colony Type Definition
## Part of the gamestate.nim decomposition refactoring.

import std/options
import ../../common/types/[core, units, planets]
import ./economy as econ_types
import ../squadron

export core.SystemId, core.HouseId
export econ_types.ConstructionProject

type
  BuildingType* {.pure.} = enum
    Infrastructure, Shipyard, ResearchLab, DefenseGrid

  Starbase* = object
    ## Orbital fortress (assets.md:2.4.4)
    id*: string                   # Unique identifier
    commissionedTurn*: int        # Turn when built
    isCrippled*: bool             # Combat state (crippled starbases provide no bonuses)

  Spaceport* = object
    ## Ground-based launch facility (assets.md:2.3.2.1)
    id*: string                   # Unique identifier
    commissionedTurn*: int        # Turn when built
    baseDocks*: int               # Base docks from config (immutable)
    effectiveDocks*: int          # Calculated: baseDocks × CST multiplier (updated on tech upgrade)
    constructionQueue*: seq[econ_types.ConstructionProject]  # Per-facility construction queue
    activeConstructions*: seq[econ_types.ConstructionProject]  # Currently building projects (up to effectiveDocks limit)

  Shipyard* = object
    ## Orbital construction facility (assets.md:2.3.2.2)
    id*: string                   # Unique identifier
    commissionedTurn*: int        # Turn when built
    baseDocks*: int               # Base docks from config (immutable)
    effectiveDocks*: int          # Calculated: baseDocks × CST multiplier (updated on tech upgrade)
    isCrippled*: bool             # Combat state (crippled shipyards can't build)
    constructionQueue*: seq[econ_types.ConstructionProject]  # Per-facility construction queue
    activeConstructions*: seq[econ_types.ConstructionProject]  # Currently building projects (up to effectiveDocks limit)

  Drydock* = object
    ## Orbital repair facility - dedicated to ship repairs only
    id*: string                   # Unique identifier
    commissionedTurn*: int        # Turn when built
    baseDocks*: int               # Base docks from config (immutable)
    effectiveDocks*: int          # Calculated: baseDocks × CST multiplier (updated on tech upgrade)
    isCrippled*: bool             # Combat state (crippled drydocks can't repair)
    repairQueue*: seq[econ_types.RepairProject]  # Per-facility repair queue
    activeRepairs*: seq[econ_types.RepairProject]  # Currently repairing (up to effectiveDocks limit)
    # NOTE: No construction queues - Drydocks are repair-only

  CapacityViolation* = object
    ## Tracks fighter capacity violations and grace period
    active*: bool                 # Is there an active violation
    violationType*: string        # "infrastructure" or "population"
    turnsRemaining*: int          # Grace period turns left (starts at 2)
    violationTurn*: int           # Turn when violation began

  TerraformProject* = object
    ## Active terraforming project on a colony
    startTurn*: int           # Turn when started
    turnsRemaining*: int      # Turns until completion
    targetClass*: int         # Target planet class (current + 1)
    ppCost*: int              # Total PP cost
    ppPaid*: int              # PP already invested

  Colony* = object
    systemId*: SystemId
    owner*: HouseId

    # Population (multiple representations for different systems)
    population*: int              # Population in millions (display field)
    souls*: int                   # Exact population count (for PTU transfers)
    populationUnits*: int         # PU: Economic production measure (from economy/types.nim)
    populationTransferUnits*: int # PTU: For colonization (~50k souls each, from economy/types.nim)

    # Infrastructure and production
    infrastructure*: int          # Infrastructure level (0-10)
    industrial*: econ_types.IndustrialUnits  # IU: Manufacturing capacity (from economy/types.nim)

    # Planet characteristics
    planetClass*: planets.PlanetClass
    resources*: planets.ResourceRating
    buildings*: seq[BuildingType]

    # Economic state (from economy/types.nim)
    production*: int              # Current turn production
    grossOutput*: int             # GCO: Cached gross colonial output for current turn
    taxRate*: int                 # 0-100 (usually house-wide, but can override per-colony)
    infrastructureDamage*: float  # 0.0-1.0, from bombardment (from economy/types.nim)

    # Construction - Dual-slot architecture (active + queue pattern)
    underConstruction*: Option[econ_types.ConstructionProject]  # Active project slot: Advances each turn, DO NOT use for validation
    constructionQueue*: seq[econ_types.ConstructionProject]     # Queued projects: Waiting for dock capacity, processed in parallel
    repairQueue*: seq[econ_types.RepairProject]      # Ships/starbases awaiting repair
    autoRepairEnabled*: bool                         # Enable automatic repair submission (defaults false, player-controlled)
    autoLoadingEnabled*: bool                        # Enable automatic fighter loading to carriers (defaults true, player-controlled)
    autoReloadETACs*: bool                           # Enable automatic PTU loading onto ETACs (defaults true, player-controlled)
    activeTerraforming*: Option[TerraformProject]    # Active terraforming project

    # Squadrons awaiting fleet assignment (auto-commissioned from construction)
    unassignedSquadrons*: seq[squadron.Squadron]          # All squadron types at colony, not in any fleet (Combat, Intel, Expansion, Auxiliary)
    # NOTE: Auto-assignment is ALWAYS enabled (see docs/architecture/standing-orders.md for rationale)

    # Fighter squadrons (assets.md:2.4.1)
    fighterSquadrons*: seq[squadron.Squadron]  # Colony-based fighters (Squadron.Fighter type)
    capacityViolation*: CapacityViolation     # Capacity violation tracking

    # Starbases (assets.md:2.4.4)
    starbases*: seq[Starbase]                 # Orbital fortresses

    # Facilities (assets.md:2.3.2)
    spaceports*: seq[Spaceport]               # Ground launch facilities
    shipyards*: seq[Shipyard]                 # Orbital construction facilities
    drydocks*: seq[Drydock]                   # Orbital repair facilities

    # Ground defenses (assets.md:2.4.7, 2.4.9)
    planetaryShieldLevel*: int                # 0=none, 1-6=SLD level
    groundBatteries*: int                     # Count of ground batteries
    armies*: int                              # Count of army divisions (AA)
    marines*: int                             # Count of marine divisions (MD)

    # Blockade status (operations.md:6.2.6)
    blockaded*: bool                          # Is colony currently under blockade
    blockadedBy*: seq[HouseId]                # Which houses are blockading (can be multiple)
    blockadeTurns*: int                       # Consecutive turns under blockade
