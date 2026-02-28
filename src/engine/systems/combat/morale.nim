## Morale System - Relative to Leading House
##
## Calculates morale tiers based on house prestige relative to the leading house.
## Per docs/specs/07-combat.md Section 7.2.3
##
## **Design:**
## - Morale reflects competitive standing, not absolute prestige values
## - Tiers are percentage thresholds of the leader's prestige
## - Handles zero-sum competition where leaders accumulate massive prestige
## - Scales naturally with any map size and prestige multiplier

import std/options
import ../../types/[core, game_state, combat, config, house]
import ../../state/[engine, iterators]
import ../../globals

proc maxPrestige*(state: GameState): int32 =
  ## Get the highest prestige among all active houses
  ## Returns at least 1 to avoid division by zero
  result = 1'i32  # Floor to avoid division by zero
  
  for house in state.allHouses():
    if house.prestige > result:
      result = house.prestige

proc moraleDRM*(state: GameState, houseId: HouseId): int32 =
  ## Calculate DRM based on house's morale tier
  ## Morale tier determined by house prestige relative to leading house
  ## Per docs/specs/07-combat.md Section 7.2.3
  
  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return 0'i32
  
  let house = houseOpt.get()
  let maxPrestige = maxPrestige(state)
  
  # Calculate percentage of leader's prestige
  let percentOfLeader = int32((float32(house.prestige) / float32(maxPrestige)) * 100.0)
  
  # Get morale tier thresholds from config
  let config = gameConfig.combat.cerModifiers.moraleDRM
  
  # Determine tier based on percentage thresholds
  if percentOfLeader <= config.crisis.maxPercent:
    return config.crisis.drm
  elif percentOfLeader <= config.veryLow.maxPercent:
    return config.veryLow.drm
  elif percentOfLeader <= config.low.maxPercent:
    return config.low.drm
  elif percentOfLeader <= config.average.maxPercent:
    return config.average.drm
  elif percentOfLeader <= config.good.maxPercent:
    return config.good.drm
  elif percentOfLeader <= config.high.maxPercent:
    return config.high.drm
  else:  # Above high threshold = VeryHigh
    return config.veryHigh.drm

proc moraleTier*(state: GameState, houseId: HouseId): MoraleTier =
  ## Get the morale tier for a house based on relative prestige
  ## Used for CER morale bonuses in combat
  
  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return MoraleTier.Collapsing
  
  let house = houseOpt.get()
  let maxPrestige = maxPrestige(state)
  
  # Calculate percentage of leader's prestige
  let percentOfLeader = int32((float32(house.prestige) / float32(maxPrestige)) * 100.0)
  
  # Get morale tier thresholds from config
  let config = gameConfig.combat.cerModifiers.moraleDRM
  
  # Determine tier based on percentage thresholds
  if percentOfLeader <= config.crisis.maxPercent:
    return MoraleTier.Collapsing
  elif percentOfLeader <= config.veryLow.maxPercent:
    return MoraleTier.VeryLow
  elif percentOfLeader <= config.low.maxPercent:
    return MoraleTier.Low
  elif percentOfLeader <= config.average.maxPercent:
    return MoraleTier.Normal
  elif percentOfLeader <= config.good.maxPercent:
    return MoraleTier.High
  elif percentOfLeader <= config.high.maxPercent:
    return MoraleTier.High  # Map "good" and "high" to same tier
  else:  # Above high threshold = VeryHigh
    return MoraleTier.VeryHigh

## Design Notes:
##
## **Relative Morale System:**
## - Morale based on `your_prestige / leader_prestige`
## - Percentage thresholds configured in combat.kdl
## - Naturally scales with zero-sum competition
##
## **Edge Cases:**
## - Leader has 0 or negative: Floor at 1 to avoid division by zero
## - You ARE the leader: 100% = VeryHigh morale
## - Everyone tied: All at 100% = VeryHigh morale
##
## **Zero-Sum Aware:**
## - As leader gains prestige from victories, thresholds rise proportionally
## - Losing houses fall into lower morale tiers relative to leader
## - No hardcoded prestige values - purely competitive standing
##
## **Map Size Independent:**
## - Works with any prestige multiplier (2x to 5x)
## - Works with any absolute prestige values
## - Starting prestige fixed at 100, but relative system handles any scale
