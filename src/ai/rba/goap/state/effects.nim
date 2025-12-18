## Action Effects System
##
## DRY Foundation: Single source of truth for action effects
## All domains use this module to define how actions modify world state

import std/[tables, options, strutils]
import ../core/types
import ../../../../common/types/[core, tech]
import ../../../../engine/intelligence/types as intel_types  # For IntelQuality

# =============================================================================
# Effect Type Registry (DRY: Centralized Definitions)
# =============================================================================

type
  EffectKind* {.pure.} = enum
    ## All possible effect types across all domains
    # Economic Effects
    ModifyTreasury,           ## treasury += delta
    ModifyProduction,         ## production += delta
    ModifyMaintenance,        ## maintenanceCost += delta
    # Military Effects
    ModifyFleetStrength,      ## totalFleetStrength += delta
    CreateFleet,              ## Add new fleet
    DestroyFleet,             ## Remove fleet
    MoveFleet,                ## Change fleet location
    # Territory Effects
    GainControl,              ## Add systemId to ownedColonies
    LoseControl,              ## Remove systemId from ownedColonies
    ColonyDefended,           ## Remove from undefendedColonies
    ColonyVulnerable,         ## Add to vulnerableColonies
    # Tech Effects
    AdvanceTech,              ## techLevels[field] += 1
    AddResearchProgress,      ## researchProgress[field] += RP
    # Diplomatic Effects
    ImproveRelations,         ## Change diplomatic state
    DeclareWar,               ## Set enemy status
    # Intelligence Effects (Phase 3: GOAP Intelligence Integration)
    ImproveIntelQuality       ## Upgrade intel quality for system

# =============================================================================
# Effect Application (Core Logic)
# =============================================================================

proc applyEffect*(state: var WorldStateSnapshot, effect: EffectRef) =
  ## Apply effect to world state (mutates state)
  ##
  ## DRY Principle: All domains use this single function
  ## No duplicated effect logic

  let kind = parseEnum[EffectKind](effect.effectId)

  case kind
  # Economic
  of ModifyTreasury:
    let delta = effect.params.getOrDefault("delta", 0)
    state.treasury += delta

  of ModifyProduction:
    let delta = effect.params.getOrDefault("delta", 0)
    state.production += delta

  of ModifyMaintenance:
    let delta = effect.params.getOrDefault("delta", 0)
    state.maintenanceCost += delta
    state.netIncome = state.production - state.maintenanceCost

  # Military
  of ModifyFleetStrength:
    let delta = effect.params.getOrDefault("delta", 0)
    state.totalFleetStrength += delta

  of CreateFleet:
    # NOTE: FleetId is string, Phase 1 placeholder
    # TODO: Proper ID mapping needed for production
    discard

  of DestroyFleet:
    # NOTE: FleetId is string, Phase 1 placeholder
    # TODO: Proper ID mapping needed for production
    discard

  of MoveFleet:
    # NOTE: Would need fleet location tracking in WorldStateSnapshot
    discard

  # Territory
  of GainControl:
    let systemId = SystemId(effect.params.getOrDefault("systemId", 0))
    if systemId notin state.ownedColonies:
      state.ownedColonies.add(systemId)

  of LoseControl:
    let systemId = SystemId(effect.params.getOrDefault("systemId", 0))
    let idx = state.ownedColonies.find(systemId)
    if idx >= 0:
      state.ownedColonies.delete(idx)

  of ColonyDefended:
    let systemId = SystemId(effect.params.getOrDefault("systemId", 0))
    let idx = state.undefendedColonies.find(systemId)
    if idx >= 0:
      state.undefendedColonies.delete(idx)

  of ColonyVulnerable:
    let systemId = SystemId(effect.params.getOrDefault("systemId", 0))
    if systemId notin state.vulnerableColonies:
      state.vulnerableColonies.add(systemId)

  # Tech
  of AdvanceTech:
    let techField = TechField(effect.params.getOrDefault("techField", 0))
    let currentLevel = state.techLevels.getOrDefault(techField, 0)
    state.techLevels[techField] = currentLevel + 1

  of AddResearchProgress:
    let techField = TechField(effect.params.getOrDefault("techField", 0))
    let rpDelta = effect.params.getOrDefault("rpDelta", 0)
    let currentRP = state.researchProgress.getOrDefault(techField, 0)
    state.researchProgress[techField] = currentRP + rpDelta

  # Diplomatic (Phase 1: placeholder - HouseId is string)
  of ImproveRelations:
    # TODO: Proper ID mapping needed for production
    discard

  of DeclareWar:
    # TODO: Proper ID mapping needed for production
    discard

  # Intelligence (Phase 3: GOAP Intelligence Integration)
  of ImproveIntelQuality:
    let systemId = SystemId(effect.params.getOrDefault("systemId", 0))
    let newQuality = effect.params.getOrDefault("quality", 0)
    # Update intel quality in snapshot
    state.systemIntelQuality[systemId] = intel_types.IntelQuality(newQuality)
    # Reset intel age to 0 (fresh intel)
    state.systemIntelAge[systemId] = 0

proc applyAllEffects*(state: var WorldStateSnapshot, effects: seq[EffectRef]) =
  ## Apply multiple effects in sequence
  for effect in effects:
    applyEffect(state, effect)

# =============================================================================
# Effect Builders (Convenience Functions)
# =============================================================================

proc createEffect*(kind: EffectKind, params: Table[string, int]): EffectRef =
  ## Create an effect with parameters
  ##
  ## Example:
  ## ```nim
  ## let eff = createEffect(ModifyTreasury, {"delta": -100}.toTable)
  ## ```
  new(result)
  result.effectId = $kind
  result.params = params

# =============================================================================
# Common Effect Builders
# =============================================================================

proc spendTreasury*(amount: int): EffectRef =
  ## Economic: Spend PP
  createEffect(ModifyTreasury, {"delta": -amount}.toTable)

proc gainTreasury*(amount: int): EffectRef =
  ## Economic: Gain PP
  createEffect(ModifyTreasury, {"delta": amount}.toTable)

proc defendColony*(systemId: SystemId): EffectRef =
  ## Military: Mark colony as defended
  createEffect(ColonyDefended, {"systemId": int(systemId)}.toTable)

proc advanceTechField*(field: TechField): EffectRef =
  ## Research: Advance tech level
  createEffect(AdvanceTech, {"techField": int(field)}.toTable)

proc addResearchPoints*(field: TechField, rp: int): EffectRef =
  ## Research: Add RP to field
  createEffect(AddResearchProgress, {"techField": int(field), "rpDelta": rp}.toTable)

proc declareWarOn*(houseId: HouseId): EffectRef =
  ## Diplomatic: Declare war (Phase 1: placeholder)
  # TODO: Proper ID mapping in Phase 2
  createEffect(DeclareWar, initTable[string, int]())

proc improveIntelQuality*(
  systemId: SystemId,
  quality: intel_types.IntelQuality
): EffectRef =
  ## Intelligence: Upgrade intel quality for system (Phase 3: GOAP Integration)
  createEffect(
    ImproveIntelQuality,
    {"systemId": int(systemId), "quality": int(quality)}.toTable
  )
