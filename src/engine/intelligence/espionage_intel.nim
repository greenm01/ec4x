## Espionage Intelligence Reporting
##
## Generates intelligence reports for espionage operations
## Per diplomacy.md:8.2 and intel.md specifications

import std/[tables, options, strformat]
import types as intel_types
import ../gamestate
import ../espionage/types as esp_types

proc generateEspionageIntelligence*(
  state: var GameState,
  result: esp_types.EspionageResult,
  turn: int
) =
  ## Generate intelligence reports for espionage operations
  ## Both attacker and target receive reports (if detected)
  ##
  ## Reports generated for:
  ## - Tech Theft: SRP stolen
  ## - Sabotage: Infrastructure damage
  ## - Assassination: Key figure eliminated
  ## - Cyber Attack: Starbase crippled
  ## - Economic Manipulation: Economy disrupted
  ## - Psyops Campaign: Morale damaged

  let actionName = case result.action
    of esp_types.EspionageAction.TechTheft: "Tech Theft"
    of esp_types.EspionageAction.SabotageLow: "Low-Impact Sabotage"
    of esp_types.EspionageAction.SabotageHigh: "High-Impact Sabotage"
    of esp_types.EspionageAction.Assassination: "Assassination"
    of esp_types.EspionageAction.CyberAttack: "Cyber Attack"
    of esp_types.EspionageAction.EconomicManipulation: "Economic Manipulation"
    of esp_types.EspionageAction.PsyopsCampaign: "Psyops Campaign"
    of esp_types.EspionageAction.CounterIntelSweep: "Counter-Intelligence Sweep"
    of esp_types.EspionageAction.IntelligenceTheft: "Intelligence Theft"
    of esp_types.EspionageAction.PlantDisinformation: "Plant Disinformation"

  if result.success:
    # Successful espionage - attacker receives intelligence on success
    let attackerDescription = case result.action
      of esp_types.EspionageAction.TechTheft:
        &"ESPIONAGE SUCCESS: Tech theft from {result.target} - stole {result.srpStolen} SRP"
      of esp_types.EspionageAction.SabotageLow, esp_types.EspionageAction.SabotageHigh:
        &"ESPIONAGE SUCCESS: Sabotage of {result.target} - destroyed {result.iuDamage} IU"
      of esp_types.EspionageAction.Assassination:
        &"ESPIONAGE SUCCESS: Assassination in {result.target} - key figure eliminated, -50% SRP gain for 1 turn"
      of esp_types.EspionageAction.CyberAttack:
        &"ESPIONAGE SUCCESS: Cyber attack on {result.target} starbase - systems crippled"
      of esp_types.EspionageAction.EconomicManipulation:
        &"ESPIONAGE SUCCESS: Economic manipulation of {result.target} - halved NCV for 1 turn"
      of esp_types.EspionageAction.PsyopsCampaign:
        &"ESPIONAGE SUCCESS: Psyops campaign against {result.target} - -25% tax revenue for 1 turn"
      of esp_types.EspionageAction.CounterIntelSweep:
        &"COUNTER-INTEL SUCCESS: Intelligence secured - enemy intel gathering blocked for 1 turn"
      of esp_types.EspionageAction.IntelligenceTheft:
        &"ESPIONAGE SUCCESS: Intelligence theft from {result.target} - entire database stolen"
      of esp_types.EspionageAction.PlantDisinformation:
        &"ESPIONAGE SUCCESS: Disinformation planted in {result.target}'s intelligence - corruption lasts 2 turns"

    let attackerReport = intel_types.ScoutEncounterReport(
      reportId: &"{result.attacker}-espionage-success-{turn}-{result.target}",
      scoutId: "intelligence-operative",
      turn: turn,
      systemId: 0.SystemId,  # Not system-specific (except sabotage/cyber)
      encounterType: intel_types.ScoutEncounterType.DiplomaticActivity,  # Covert operations
      observedHouses: @[result.target],
      fleetDetails: @[],
      colonyDetails: none(intel_types.ColonyIntelReport),
      fleetMovements: @[],
      description: attackerDescription,
      significance: 8  # Successful espionage is highly significant
    )

    # CRITICAL: Get, modify, write back to persist
    var attackerHouse = state.houses[result.attacker]
    attackerHouse.intelligence.addScoutEncounter(attackerReport)
    state.houses[result.attacker] = attackerHouse

    # If NOT detected, target remains unaware (no intelligence report)
    # This is intentional - undetected espionage is covert

  if result.detected:
    # Failed/detected espionage - target receives intelligence on the attempt
    let targetDescription = if result.success:
      # Detected but successful (rare - target knows they were hit)
      &"ESPIONAGE DETECTED: {result.attacker} conducted {actionName} against your house. Operation succeeded despite detection."
    else:
      # Detected and failed (common)
      &"ESPIONAGE DETECTED: {result.attacker} attempted {actionName} against your house. Operation thwarted by counter-intelligence."

    let targetReport = intel_types.ScoutEncounterReport(
      reportId: &"{result.target}-espionage-detected-{turn}-{result.attacker}",
      scoutId: "counter-intelligence",
      turn: turn,
      systemId: 0.SystemId,
      encounterType: intel_types.ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[result.attacker],
      fleetDetails: @[],
      colonyDetails: none(intel_types.ColonyIntelReport),
      fleetMovements: @[],
      description: targetDescription,
      significance: if result.success: 9 else: 7  # Higher if they succeeded despite detection
    )

    # Add to espionage activity log (per intel.md:types.nim EspionageActivityReport)
    let activityReport = intel_types.EspionageActivityReport(
      turn: turn,
      perpetrator: result.attacker,
      action: actionName,
      targetSystem: none(SystemId),  # TODO: Add system for sabotage/cyber attacks
      detected: true,
      description: if result.success:
        &"{result.attacker} successfully conducted {actionName} (detected)"
      else:
        &"{result.attacker} failed {actionName} attempt (detected and blocked)"
    )

    # CRITICAL: Get target house once, add both reports, write back to persist
    var targetHouse = state.houses[result.target]
    targetHouse.intelligence.addScoutEncounter(targetReport)
    targetHouse.intelligence.addEspionageActivity(activityReport)
    state.houses[result.target] = targetHouse

    # If espionage was detected, attacker also knows they were detected
    if not result.success:
      let attackerFailureReport = intel_types.ScoutEncounterReport(
        reportId: &"{result.attacker}-espionage-failed-{turn}-{result.target}",
        scoutId: "intelligence-operative",
        turn: turn,
        systemId: 0.SystemId,
        encounterType: intel_types.ScoutEncounterType.DiplomaticActivity,
        observedHouses: @[result.target],
        fleetDetails: @[],
        colonyDetails: none(intel_types.ColonyIntelReport),
        fleetMovements: @[],
        description: &"ESPIONAGE FAILED: {actionName} against {result.target} was detected and blocked by counter-intelligence.",
        significance: 6  # Failed espionage is moderately significant (prestige loss)
      )

      # CRITICAL: Get, modify, write back to persist
      var attackerHouse = state.houses[result.attacker]
      attackerHouse.intelligence.addScoutEncounter(attackerFailureReport)
      state.houses[result.attacker] = attackerHouse
