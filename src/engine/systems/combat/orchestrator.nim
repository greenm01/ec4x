## Theater Progression Orchestrator
##
## Enforces Space → Orbital → Planetary combat sequence per spec 07-combat.md:9-70
## Ensures attackers must win each theater before advancing to the next.
##
## Architecture: Single entry point for all combat in a system, replacing
## separate calls to resolveBattle() and resolvePlanetaryCombat().

import std/[tables, options, random]
import ../../../common/logger
import ../../types/[core, game_state, command]
import ../../types/resolution as res_types
import ../../state/[entity_manager, iterators]
import battles # Space + Orbital combat
import planetary # Planetary combat (bombardment, invasion, blitz)

type
  TheaterResult* = object
    ## Result from a single combat theater
    attackersWon*: bool
    defenderWon*: bool
    wasStalemate*: bool
    survivingAttackers*: seq[HouseId] # Houses that survived this theater

  SystemCombatOutcome* = object
    ## Complete outcome of all combat theaters in a system
    systemId*: SystemId
    spaceResult*: Option[TheaterResult]
    orbitalResult*: Option[TheaterResult]
    planetaryAttacks*: int # Number of bombardment/invasion attempts

proc determineTheaterOutcome(
    combatReports: seq[CombatReport], systemOwner: Option[HouseId]
): TheaterResult =
  ## Analyze combat reports to determine if attackers won the theater
  ## Attackers win if: defender eliminated OR defender retreated
  ## Defender wins if: all attackers eliminated OR all attackers retreated
  ## Stalemate if: combat ended with both sides present

  result = TheaterResult(
    attackersWon: false,
    defenderWon: false,
    wasStalemate: false,
    survivingAttackers: @[],
  )

  if combatReports.len == 0:
    # No combat occurred - attackers advance by default
    result.attackersWon = true
    return

  # TODO: Implement theater outcome analysis from combat reports
  # For now, assume attackers always win if they have surviving forces
  # This needs to be enhanced based on actual CombatResult structure

  result.attackersWon = true

proc resolveSystemCombat*(
    state: var GameState,
    systemId: SystemId,
    orders: Table[HouseId, OrderPacket],
    arrivedOrders: Table[HouseId, OrderPacket],
    combatReports: var seq[CombatReport],
    events: var seq[res_types.GameEvent],
    rng: var Rand,
) =
  ## Single entry point for all combat in a system
  ## Enforces theater progression: Space → Orbital → Planetary
  ##
  ## Args:
  ##   orders: All orders (for space/orbital combat - no arrival required)
  ##   arrivedOrders: Only orders from arrived fleets (for planetary combat)
  ##
  ## Theater 1 (Space): Mobile fleets vs mobile fleets
  ## Theater 2 (Orbital): Surviving attackers vs starbases + orbital defenders
  ## Theater 3 (Planetary): Attackers with orbital supremacy vs ground defenses

  logCombat("[THEATER] Resolving combat", " system=", $systemId)

  let colonyOpt = state.colonies.entities.entity(systemId)
  let systemOwner =
    if colonyOpt.isSome:
      some(colonyOpt.get().owner)
    else:
      none(HouseId)

  # THEATER 1 & 2: Space + Orbital Combat (handled by battles.nim)
  # resolveBattle() already implements proper space → orbital progression
  # Uses 'orders' (all orders - space/orbital don't require arrival)
  let reportCountBefore = combatReports.len
  battles.resolveBattle(state, systemId, orders, combatReports, events, rng)
  let reportCountAfter = combatReports.len

  # Determine if attackers achieved orbital supremacy
  # For now, analyze combat reports to see if attackers survived
  # TODO: Enhance with proper victor analysis from CombatResult

  var attackersAchievedOrbitalSupremacy = false

  if systemOwner.isNone:
    # No colony = no orbital defense = attackers have supremacy by default
    attackersAchievedOrbitalSupremacy = true
  elif reportCountAfter == reportCountBefore:
    # No combat occurred = no defenders = attackers have supremacy
    attackersAchievedOrbitalSupremacy = true
  else:
    # Combat occurred - check if attackers won
    # For now, assume attackers won if any non-owner fleets remain in system
    # TODO: This needs proper victor analysis from CombatResult

    var hasNonOwnerFleets = false
    for (fleetId, fleet) in state.fleetsAtSystemWithId(systemId):
      if systemOwner.isSome and fleet.houseId != systemOwner.get():
        hasNonOwnerFleets = true
        break

    attackersAchievedOrbitalSupremacy = hasNonOwnerFleets

  # THEATER 3: Planetary Combat (bombardment, invasion, blitz)
  # Only proceed if attackers achieved orbital supremacy
  # Uses 'arrivedOrders' (planetary combat requires arrived fleets)
  if attackersAchievedOrbitalSupremacy:
    logCombat(
      "[THEATER] Attackers achieved orbital supremacy", " system=", $systemId
    )

    # Execute planetary combat for orders from arrived fleets
    let planetaryResults =
      planetary.resolvePlanetaryCombat(state, arrivedOrders, rng, events)

    logCombat(
      "[THEATER] Planetary combat complete",
      " system=",
      $systemId,
      " attacks=",
      $planetaryResults.len,
    )

    # Clear arrivedFleets for executed planetary combat orders
    for result in planetaryResults:
      if result.fleetId in state.arrivedFleets:
        state.arrivedFleets.del(result.fleetId)
        logDebug(
          "Conflict", "Cleared arrival status", "fleetId=", $result.fleetId
        )
  else:
    logCombat(
      "[THEATER] Attackers did not achieve orbital supremacy - planetary combat blocked",
      " system=",
      $systemId,
    )
