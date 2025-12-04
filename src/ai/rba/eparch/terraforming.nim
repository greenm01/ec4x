## Eparch Terraforming Module
##
## Byzantine Eparch - Imperial Prefect of Economy
##
## Strategic terraforming and planetary development decision-making

import std/[random, algorithm]
import ../../../common/types/[core, planets]
import ../../../engine/[gamestate, fog_of_war, orders]
import ../controller_types
import ../config  # RBA configuration system

export core, orders

proc generateTerraformOrders*(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[TerraformOrder] =
  ## Generate terraforming upgrade orders for planet class improvements
  ## Per economy.md Section 4.7 and assets.md Section 2.2
  ##
  ## Strategy:
  ## - Upgrade high-value colonies (good resources, strategic location)
  ## - Requires TER tech level to allow upgrade (TER level >= target class)
  ## - Costs 60-2000 PP depending on target class
  ## - Takes 1-5 turns depending on TER level
  result = @[]
  let p = controller.personality
  let house = filtered.ownHouse

  # Economic AIs prioritize terraforming for long-term growth
  # Lower threshold to 0.4 so more AIs use this feature
  if p.economicFocus < 0.4:
    return result

  # Need healthy treasury (upgrades are expensive)
  if house.treasury < 800:
    return result

  # Check TER tech level
  let terLevel = house.techTree.levels.terraformingTech
  if terLevel < 1:
    return result  # No terraforming tech yet

  # Find colonies that can be upgraded
  type UpgradeCandidate = tuple[systemId: SystemId, currentClass: int, value: float, cost: int]
  var candidates: seq[UpgradeCandidate] = @[]

  for colony in filtered.ownColonies:
    if colony.owner != controller.houseId:
      continue

    # Check if colony can be upgraded
    # Planet class: 0=Extreme, 1=Desolate, 2=Hostile, 3=Harsh, 4=Benign, 5=Lush, 6=Eden
    # ownColonies are full Colony objects (not VisibleColony), so planetClass is direct
    let currentClass = int(colony.planetClass)
    let targetClass = currentClass + 1

    # Can't upgrade beyond Eden (class 6)
    if targetClass > 6:
      continue

    # Need TER tech level >= target class to upgrade
    # TER 1 allows upgrade to Desolate (class 1)
    # TER 2 allows upgrade to Hostile (class 2), etc.
    if terLevel < targetClass:
      continue

    # Calculate upgrade cost (from config, based on economy.md:4.7)
    let cost = case targetClass
      of 1: globalRBAConfig.economic.terraforming_costs_extreme_to_desolate     # Extreme → Desolate
      of 2: globalRBAConfig.economic.terraforming_costs_desolate_to_hostile    # Desolate → Hostile
      of 3: globalRBAConfig.economic.terraforming_costs_hostile_to_harsh       # Hostile → Harsh
      of 4: globalRBAConfig.economic.terraforming_costs_harsh_to_benign        # Harsh → Benign
      of 5: globalRBAConfig.economic.terraforming_costs_benign_to_lush         # Benign → Lush
      of 6: globalRBAConfig.economic.terraforming_costs_lush_to_eden           # Lush → Eden
      else: 1000

    # Skip if we can't afford it
    if house.treasury < cost + 200:  # Keep 200 PP reserve
      continue

    # Calculate colony value (prioritize good resources and high infrastructure)
    # ownColonies are full Colony objects, so fields are direct (not Option)
    var value = float(colony.infrastructure) * 2.0  # Infrastructure is key

    # Bonus for good resources (great ROI on rich planets)
    case colony.resources
    of ResourceRating.VeryRich: value *= 3.0  # HIGHEST priority
    of ResourceRating.Rich: value *= 2.0
    of ResourceRating.Abundant: value *= 1.5
    else: value *= 0.5  # Low priority for poor resources

    # Bonus for strategic location (homeworld, hub, etc.)
    # We can't easily check this in filtered state, so use population as proxy
    if colony.population > 200:
      value *= 1.5  # Established, important colony

    candidates.add((systemId: colony.systemId, currentClass: currentClass,
                    value: value, cost: cost))

  if candidates.len == 0:
    return result

  # Sort by value/cost ratio (best ROI first)
  candidates.sort(proc(a, b: UpgradeCandidate): int =
    let ratioA = a.value / float(a.cost)
    let ratioB = b.value / float(b.cost)
    if ratioB > ratioA: 1
    elif ratioB < ratioA: -1
    else: 0
  )

  # Upgrade one colony per turn (expensive)
  let best = candidates[0]

  # Calculate turns remaining based on TER level (higher TER = faster)
  # Estimate: 5 turns at TER1, down to 1 turn at TER5+
  let turnsRemaining = max(1, 6 - terLevel)

  result.add(TerraformOrder(
    colonySystem: best.systemId,
    startTurn: filtered.turn,
    turnsRemaining: turnsRemaining,
    ppCost: best.cost,
    targetClass: best.currentClass + 1
  ))
