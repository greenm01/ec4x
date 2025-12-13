## EC4X Core Identifiers
## Basic ID types used throughout the codebase

# =============================================================================
# Core Game Identifiers
# =============================================================================

type
  HouseId* = string      ## Unique identifier for a House (player faction)
  FleetId* = string      ## Unique identifier for a fleet
  SystemId* = uint       ## System ID from hex coordinates on star map
  SquadronId* = string   ## Unique identifier for a squadron
  ColonyId* = string     ## Unique identifier for a colony

  FleetMissionState* {.pure.} = enum
    ## State machine for fleet spy missions
    None,           # Normal fleet operation
    Traveling,      # En route to spy mission target
    OnSpyMission,   # Active spy mission (locked, gathering intel)
    Detected        # Detected during spy mission (destroyed next phase)
