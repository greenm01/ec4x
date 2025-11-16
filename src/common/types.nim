## EC4X Common Types
## Shared type definitions used across the entire codebase
## Based on EC4X specifications

# =============================================================================
# Core Game Identifiers
# =============================================================================

type
  HouseId* = string      ## Unique identifier for a House (player faction)
  FleetId* = string      ## Unique identifier for a fleet
  SystemId* = uint       ## System ID from hex coordinates on star map
  SquadronId* = string   ## Unique identifier for a squadron
  ColonyId* = string     ## Unique identifier for a colony

# =============================================================================
# Star Map and Lane Types
# =============================================================================

type
  LaneType* {.pure.} = enum
    ## Jump lane classifications (hardcoded)
    ## Determines movement restrictions per game specs
    Major        ## Standard lanes, 2 jumps/turn if owned
    Minor        ## 1 jump/turn
    Restricted   ## 1 jump/turn, no crippled/spacelift ships

# =============================================================================
# Ship Types and Stats
# =============================================================================

type
  ShipClass* {.pure.} = enum
    ## All hardcoded ship classes in EC4X
    ## 17 ship types total - no custom ships allowed
    Fighter
    Scout
    Raider
    Destroyer
    Cruiser
    LightCruiser
    HeavyCruiser
    Battlecruiser
    Battleship
    Dreadnought
    SuperDreadnought
    Carrier
    SuperCarrier
    Starbase
    ETAC
    TroopTransport
    PlanetBreaker

  ShipStats* = object
    ## Combat and operational statistics for a ship
    name*: string
    class*: string
    attackStrength*: int     # AS - offensive firepower
    defenseStrength*: int    # DS - defensive shielding
    commandCost*: int        # CC - cost to assign to squadron
    commandRating*: int      # CR - for flagships, capacity to lead
    techLevel*: int          # Minimum tech level to build
    buildCost*: int          # Production cost to construct
    upkeepCost*: int         # Per-turn maintenance cost
    specialCapability*: string  # ELI, CLK, or empty
    carryLimit*: int         # For carriers, transports (0 if N/A)

  ShipType* {.pure.} = enum
    ## Ship category
    Military     ## Combat-capable warship
    Spacelift    ## Non-combat support vessel

# =============================================================================
# Ground Unit Types and Stats
# =============================================================================

type
  GroundUnitType* {.pure.} = enum
    ## All hardcoded ground unit types in EC4X
    ## 4 unit types total - no custom units allowed
    PlanetaryShield
    GroundBattery
    Army
    MarineDivision

  GroundUnitStats* = object
    ## Statistics for ground-based military units
    name*: string
    class*: string
    cstMin*: int            # Minimum CST tech level
    buildCost*: int         # Production cost
    upkeepCost*: int        # Per-turn maintenance
    attackStrength*: int    # AS - offensive power
    defenseStrength*: int   # DS - defensive power
    buildTime*: int         # Turns to construct
    maxPerPlanet*: int      # Max allowed per planet (-1 = unlimited)

# =============================================================================
# Facility Types and Stats
# =============================================================================

type
  FacilityType* {.pure.} = enum
    ## All hardcoded facility types in EC4X
    ## 2 facility types total - no custom facilities allowed
    Spaceport
    Shipyard

  FacilityStats* = object
    ## Statistics for orbital and planetary infrastructure
    name*: string
    class*: string
    cstMin*: int            # Minimum CST tech level
    buildCost*: int         # Production cost
    upkeepCost*: int        # Per-turn maintenance
    defenseStrength*: int   # DS - defensive power
    carryLimit*: int        # Capacity (for construction)
    buildTime*: int         # Turns to construct
    docks*: int             # Number of construction docks
    maxPerPlanet*: int      # Max allowed per planet (-1 = unlimited)

# =============================================================================
# Planet and Colony Types
# =============================================================================

type
  PlanetClass* {.pure.} = enum
    ## Planet habitability classifications
    ## Determines population and infrastructure limits
    Extreme      # Level I   - 1-20 PU
    Desolate     # Level II  - 21-60 PU
    Hostile      # Level III - 61-180 PU
    Harsh        # Level IV  - 181-500 PU
    Benign       # Level V   - 501-1000 PU
    Lush         # Level VI  - 1k-2k PU
    Eden         # Level VII - 2k+ PU

  ResourceRating* {.pure.} = enum
    ## System resource availability
    VeryPoor
    Poor
    Abundant
    Rich
    VeryRich

# =============================================================================
# Technology Types
# =============================================================================

type
  TechField* {.pure.} = enum
    ## Seven tech fields in EC4X (hardcoded)
    EnergyLevel              # EL
    ShieldLevel              # SL
    ConstructionTech         # CST
    WeaponsTech              # WEP
    TerraformingTech         # TER
    ElectronicIntelligence   # ELI
    CounterIntelligence      # CIC

  TechLevel* = object
    ## Tech levels for all fields
    energyLevel*: int              # EL (0-10)
    shieldLevel*: int              # SL (0-10)
    constructionTech*: int         # CST (0-10)
    weaponsTech*: int              # WEP (0-10)
    terraformingTech*: int         # TER (0-10)
    electronicIntelligence*: int   # ELI (0-10)
    counterIntelligence*: int      # CIC (0-10)

# =============================================================================
# Diplomatic and Prestige Types
# =============================================================================

type
  DiplomaticState* {.pure.} = enum
    ## Relations between houses (hardcoded)
    Neutral          # Default state
    NonAggression    # Formal non-aggression pact
    Enemy            # At war

  PrestigeChange* = object
    ## Record of prestige gain/loss
    house*: HouseId
    amount*: int
    reason*: string
    turn*: int

# =============================================================================
# Combat Types
# =============================================================================

type
  CombatState* {.pure.} = enum
    ## Unit combat readiness
    Undamaged
    Crippled
    Destroyed

  CombatEffectivenessRating* = float  ## CER multiplier (0.25 to 2.0)
