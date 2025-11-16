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
# Ship Types and Stats
# =============================================================================

type
  ShipClass* = enum
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

  ShipType* = enum
    ## Ship category
    Military     ## Combat-capable warship
    Spacelift    ## Non-combat support vessel

# =============================================================================
# Ground Unit Types and Stats
# =============================================================================

type
  GroundUnitType* = enum
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
  FacilityType* = enum
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
  PlanetClass* = enum
    ## Planet habitability classifications
    ## Determines population and infrastructure limits
    pcExtreme      # Level I   - 1-20 PU
    pcDesolate     # Level II  - 21-60 PU
    pcHostile      # Level III - 61-180 PU
    pcHarsh        # Level IV  - 181-500 PU
    pcBenign       # Level V   - 501-1000 PU
    pcLush         # Level VI  - 1k-2k PU
    pcEden         # Level VII - 2k+ PU

  ResourceRating* = enum
    ## System resource availability
    rrVeryPoor
    rrPoor
    rrAbundant
    rrRich
    rrVeryRich

# =============================================================================
# Technology Types
# =============================================================================

type
  TechField* = enum
    ## Seven tech fields in EC4X (hardcoded)
    tfEL   # Energy Level
    tfSL   # Shield Level
    tfCST  # Construction Tech
    tfWEP  # Weapons Tech
    tfTER  # Terraforming Tech
    tfELI  # Electronic Intelligence
    tfCIC  # Counter Intelligence Command

  TechLevel* = object
    ## Tech levels for all fields
    EL*: int    # Energy Level (0-10)
    SL*: int    # Shield Level (0-10)
    CST*: int   # Construction Tech (0-10)
    WEP*: int   # Weapons Tech (0-10)
    TER*: int   # Terraforming Tech (0-10)
    ELI*: int   # Electronic Intelligence (0-10)
    CIC*: int   # Counter Intelligence Command (0-10)

# =============================================================================
# Diplomatic and Prestige Types
# =============================================================================

type
  DiplomaticState* = enum
    ## Relations between houses (hardcoded)
    dsNeutral          # Default state
    dsNonAggression    # Formal non-aggression pact
    dsEnemy            # At war

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
  CombatState* = enum
    ## Unit combat readiness
    csUndamaged
    csCrippled
    csDestroyed

  CombatEffectivenessRating* = float  ## CER multiplier (0.25 to 2.0)
