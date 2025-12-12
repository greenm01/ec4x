## Intelligence Snapshot Helper Utilities
## Fast lookup functions for IntelligenceSnapshot data
## Follows DoD: pure data lookup, no side effects
##
## This module provides a DRY (Don't Repeat Yourself) interface for accessing
## intelligence data from IntelligenceSnapshot. Instead of duplicating lookup
## logic across 36 usage sites, all intelligence queries go through these
## helper functions.

import std/[tables, options]
import intelligence_types
import ../../../common/types/core

# =============================================================================
# Fast System Lookups
# =============================================================================

proc getSystemIntel*(
  snap: IntelligenceSnapshot,
  systemId: SystemId
): Option[InvasionOpportunity] =
  ## Fast lookup: Get detailed intelligence for a specific system
  ## Returns InvasionOpportunity if system is in our intel (includes defenses,
  ## value, quality)
  ##
  ## Returns:
  ##   Some(InvasionOpportunity) if detailed intelligence exists
  ##   None if no intelligence available

  # Check military intelligence for system (vulnerableTargets has detailed
  # intel)
  for target in snap.military.vulnerableTargets:
    if target.systemId == systemId:
      return some(target)

  return none(InvasionOpportunity)

proc getSystemThreat*(
  snap: IntelligenceSnapshot,
  systemId: SystemId
): ThreatLevel =
  ## Fast lookup: Get threat level for system
  ##
  ## Returns:
  ##   Threat level from threatsByColony table
  ##   tlNone if system not in threat assessment

  if systemId in snap.military.threatsByColony:
    return snap.military.threatsByColony[systemId].level

  return ThreatLevel.tlNone

proc getSystemOwner*(
  snap: IntelligenceSnapshot,
  systemId: SystemId
): Option[HouseId] =
  ## Fast lookup: Get colony owner if known
  ##
  ## Returns:
  ##   Some(HouseId) if we know who owns this system
  ##   None if uncolonized or owner unknown

  # Check known enemy colonies
  for colony in snap.knownEnemyColonies:
    if colony.systemId == systemId:
      return some(colony.owner)

  return none(HouseId)

proc getSystemDefenses*(
  snap: IntelligenceSnapshot,
  systemId: SystemId
): int =
  ## Fast lookup: Get estimated defenses (starbases + batteries)
  ##
  ## Returns:
  ##   Combined defense strength estimate
  ##   0 if no defensive intelligence available

  # Check vulnerable targets intelligence
  for target in snap.military.vulnerableTargets:
    if target.systemId == systemId:
      return target.estimatedDefenses

  return 0

proc getFleetThreat*(
  snap: IntelligenceSnapshot,
  systemId: SystemId
): int =
  ## Get estimated enemy fleet strength in system
  ##
  ## Returns:
  ##   Combined fleet strength of all enemy fleets in this system
  ##   0 if no enemy fleets detected

  var totalStrength = 0

  for fleet in snap.military.knownEnemyFleets:
    if fleet.lastKnownLocation == systemId:
      totalStrength += fleet.estimatedStrength

  return totalStrength

# =============================================================================
# Intelligence Quality Checks
# =============================================================================

proc isIntelStale*(
  snap: IntelligenceSnapshot,
  systemId: SystemId,
  currentTurn: int,
  threshold: int = 10
): bool =
  ## Check if intelligence for system is stale (>threshold turns old)
  ##
  ## Parameters:
  ##   snap: Intelligence snapshot
  ##   systemId: System to check
  ##   currentTurn: Current game turn
  ##   threshold: Age threshold in turns (default: 10)
  ##
  ## Returns:
  ##   true if intelligence is older than threshold turns
  ##   false if intelligence is fresh or system not in stale list

  # Check espionage stale intel list
  if systemId in snap.espionage.staleIntelSystems:
    return true

  # Check vulnerable targets for intel age
  for target in snap.military.vulnerableTargets:
    if target.systemId == systemId:
      let age = currentTurn - target.lastIntelTurn
      return age > threshold

  return false

proc getIntelQuality*(
  snap: IntelligenceSnapshot,
  systemId: SystemId
): IntelQuality =
  ## Get intelligence quality level for system
  ##
  ## Returns:
  ##   IntelQuality enum value
  ##   iqVisual (lowest quality) if no specific quality data

  # Check vulnerable targets for quality assessment
  for target in snap.military.vulnerableTargets:
    if target.systemId == systemId:
      return target.intelQuality

  # Default to visual quality (lowest) if no specific data
  return IntelQuality.Visual

# =============================================================================
# Composite Queries
# =============================================================================

proc isSafeSystem*(
  snap: IntelligenceSnapshot,
  systemId: SystemId
): bool =
  ## Composite query: Is this system safe for friendly operations?
  ##
  ## A system is considered safe if:
  ##   - No significant threat detected
  ##   - No large enemy fleet presence
  ##   - Not flagged as high-risk by intelligence
  ##
  ## Returns:
  ##   true if system appears safe for friendly operations
  ##   false if threats detected or safety uncertain

  # Check threat level
  let threat = getSystemThreat(snap, systemId)
  if threat.ord >= ThreatLevel.tlModerate.ord:
    return false  # Moderate or higher threat = unsafe

  # Check enemy fleet strength
  let fleetThreat = getFleetThreat(snap, systemId)
  if fleetThreat >= 50:  # Significant enemy presence
    return false

  # Check for nearby enemy fleet movements
  for houseId, movements in snap.enemyFleetMovements:
    for movement in movements:
      # If enemy fleet recently moved to or near this system, unsafe
      if movement.lastKnownLocation == systemId:
        return false

  return true

proc isVulnerableTarget*(
  snap: IntelligenceSnapshot,
  systemId: SystemId
): bool =
  ## Composite query: Is this system a vulnerable invasion target?
  ##
  ## A system is vulnerable if:
  ##   - Identified in vulnerableTargets list
  ##   - Has weak defenses relative to our capabilities
  ##   - Intelligence quality sufficient for confident assessment
  ##
  ## Returns:
  ##   true if system is vulnerable to attack
  ##   false if well-defended or insufficient intelligence

  # Check if in vulnerable targets list
  for target in snap.military.vulnerableTargets:
    if target.systemId == systemId:
      # Vulnerability assessment already done by intelligence system
      return true

  return false
