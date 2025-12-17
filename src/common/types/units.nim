## EC4X Unit Types
## Ship, ground unit, and facility definitions

# =============================================================================
# Ship Types and Stats
# =============================================================================

type
  ShipClass* {.pure.} = enum
    ## All hardcoded ship classes in EC4X
    ## 18 ship types total - no custom ships allowed
    ##
    ## NOTE: Starbases are FACILITIES, not ships (completely removed from ShipClass)
    ## - Built via Eparch as facility (Spaceport → Shipyard → Starbase)
    ## - Stored in colony.starbases (not fleets/squadrons)
    ## - Combat uses facility stats from facilities.toml, not ShipClass
    ## - Special TargetBucket.Starbase enum value handles combat targeting
    Fighter
    Corvette
    Frigate
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
    ETAC
    TroopTransport
    PlanetBreaker

  ShipRole* {.pure.} = enum
    ## Ship operational role classification
    ## Determines capacity limits and strategic usage
    Escort         # Combat-capable, CR < 7, not capacity-limited
    Capital        # Flagship-capable, CR >= 7, subject to capital squadron limits
    Auxiliary      # Non-combat support (ETAC, TroopTransport)
    SpecialWeapon  # Unique strategic units (PlanetBreaker, Starbase)
    Fighter        # Embarked strike craft, special capacity rules

  ShipStats* = object
    ## Combat and operational statistics for a ship
    name*: string
    class*: string
    role*: ShipRole          # Operational role classification
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
    Spacelift    ## Non-combat transport vessel (ETAC/TroopTransport)

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
