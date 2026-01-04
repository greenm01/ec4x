## Intelligence System Engine
##
## Main orchestrator and public API for the intelligence system.
## Coordinates all intelligence gathering, processing, and management subsystems.
##
## Architecture:
## - Orchestrates specialized intel modules (scout, espionage, combat, etc.)
## - Provides high-level public API for intelligence operations
## - Delegates to specialized modules for implementation details
## - Maintains separation between intel gathering and intel storage

import std/[tables, options]
import ../types/[game_state, core, intel, fleet, espionage]
import ./[generator, corruption]

export generator  # Re-export common report generation functions
export IntelQuality  # Re-export quality levels
export OngoingEffect  # Re-export for corruption checking

# ============================================================================
# High-Level Intelligence Gathering API
# ============================================================================

proc gatherSystemIntel*(
    state: GameState, systemId: SystemId, houseId: HouseId, quality: IntelQuality
): Option[SystemIntelPackage] =
  ## Gather all available intelligence about a system
  ##
  ## Returns:
  ## - SystemIntelPackage with fleet and squadron intel
  ## - None if no intelligence available (no fleets, no colony)
  ##
  ## Quality levels:
  ## - Visual: Basic fleet composition, ship counts
  ## - Spy: Tech levels, hull integrity, embarked fighters
  ##
  ## Used by:
  ## - Scout missions (Spy quality)
  ## - Visual encounters (Visual quality)
  ## - Espionage operations (Spy quality)
  return generator.generateSystemIntelReport(state, houseId, systemId, quality)

proc gatherColonyIntel*(
    state: GameState, systemId: SystemId, houseId: HouseId, quality: IntelQuality
): Option[ColonyIntelReport] =
  ## Gather intelligence about a colony's ground assets and economy
  ##
  ## Returns:
  ## - ColonyIntelReport with population, infrastructure, ground forces
  ## - Spy quality includes construction queue and economic data
  ## - None if no colony or gathering own colony
  ##
  ## Used by:
  ## - SpyOnPlanet missions (Spy quality)
  ## - Scout observations (Spy quality)
  return generator.generateColonyIntelReport(state, houseId, systemId, quality)

proc gatherOrbitalIntel*(
    state: GameState, systemId: SystemId, houseId: HouseId, quality: IntelQuality
): Option[OrbitalIntelReport] =
  ## Gather intelligence about orbital assets at a colony
  ##
  ## Returns:
  ## - OrbitalIntelReport with starbases, shipyards, fighter squadrons
  ## - Spy quality includes guard/blockade fleet identification
  ## - None if no colony or gathering own colony
  ##
  ## Used by:
  ## - Approach/orbital missions
  ## - Scout observations (Spy quality)
  return generator.generateOrbitalIntelReport(state, houseId, systemId, quality)

proc gatherStarbaseIntel*(
    state: GameState, systemId: SystemId, houseId: HouseId, quality: IntelQuality
): Option[StarbaseIntelReport] =
  ## Gather economic and R&D intelligence from starbase
  ##
  ## Returns:
  ## - StarbaseIntelReport with treasury, income, tech levels, research
  ## - None if no starbase or gathering own starbase
  ##
  ## Used by:
  ## - HackStarbase missions (Spy quality)
  return generator.generateStarbaseIntelReport(state, houseId, systemId, quality)

# ============================================================================
# Intelligence Database Access
# ============================================================================

proc hasIntelDatabase*(state: GameState, houseId: HouseId): bool =
  ## Check if a house has an intelligence database
  return state.intel.contains(houseId)

proc getIntelDatabase*(
    state: GameState, houseId: HouseId
): Option[IntelDatabase] =
  ## Retrieve a house's intelligence database
  if not state.intel.contains(houseId):
    return none(IntelDatabase)
  return some(state.intel[houseId])

# ============================================================================
# Intelligence Corruption API
# ============================================================================

proc hasIntelCorruption*(
    state: GameState, houseId: HouseId
): Option[OngoingEffect] =
  ## Check if a house's intelligence is corrupted
  ##
  ## Returns:
  ## - Some(OngoingEffect) with IntelCorrupted type if corrupted
  ## - None if intelligence is clean
  ##
  ## Used by:
  ## - Report generation to apply corruption
  ## - UI to display corruption warnings
  return corruption.hasIntelCorruption(state.ongoingEffects, houseId)

# ============================================================================
# Utility Functions
# ============================================================================

proc isScoutFleet*(fleet: Fleet): bool =
  ## Check if a fleet is a scout fleet
  ## Scout fleets automatically gather Spy-quality intelligence
  ##
  ## Future: Implement proper fleet role detection
  ## For now, placeholder returns false
  return false

proc getIntelStaleness*(gatheredTurn: int32, currentTurn: int32): int32 =
  ## Calculate how many turns old intelligence is
  ##
  ## Returns:
  ## - 0: Current turn (fresh)
  ## - 1+: Turns since gathered (stale)
  return currentTurn - gatheredTurn

proc isIntelStale*(gatheredTurn: int32, currentTurn: int32, threshold: int32 = 3): bool =
  ## Check if intelligence is stale (older than threshold)
  ##
  ## Default threshold: 3 turns
  return getIntelStaleness(gatheredTurn, currentTurn) > threshold

# ============================================================================
# Design Notes
# ============================================================================
##
## **Architecture Pattern:**
##
## Intel Engine follows the standard system module pattern:
## - engine.nim: High-level API and orchestration (this file)
## - generator.nim: Low-level report generation (utility module)
## - *_intel.nim: Specialized intel subsystems (scout, espionage, combat, etc.)
## - corruption.nim: Intel corruption mechanics
## - detection.nim: Cloaking and detection mechanics
##
## **Separation of Concerns:**
##
## 1. **Intelligence Gathering** (this module):
##    - Coordinates report generation
##    - Provides public API
##    - Quality level management
##
## 2. **Intelligence Storage** (caller responsibility):
##    - Storing reports in IntelligenceDatabase
##    - Managing intel lifetime and staleness
##    - Querying historical intelligence
##
## 3. **Intelligence Processing** (specialized modules):
##    - scout_intel.nim: Scout mission processing
##    - espionage_intel.nim: Espionage operation intel
##    - combat_intel.nim: Combat encounter intel
##    - event_processor: Event-driven intel updates
##
## **Usage Example:**
##
## ```nim
## import ../intel/engine
##
## # Gather system intel from a scout mission
## let systemIntel = intel.gatherSystemIntel(
##   state, targetSystem, scoutOwner, IntelQuality.Spy
## )
##
## if systemIntel.isSome:
##   let package = systemIntel.get()
##   # Store in intelligence database
##   storeIntelPackage(state, scoutOwner, package)
## ```
##
## **Quality Levels:**
##
## - Visual: Basic observation (ship types, counts)
## - Spy: Detailed intelligence (tech, damage, cargo, queues)
## - Perfect: Complete accuracy (own assets, fog-of-war exempt)
##
## **Future Enhancements:**
##
## - Intelligence decay over time
## - Intel sharing between allied houses
## - Misinformation campaigns
## - Pattern analysis (fleet movement tracking)
## - Predictive intelligence
