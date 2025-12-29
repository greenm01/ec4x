## Espionage Intelligence Reporting
##
## Generates intelligence reports for espionage operations
## Per diplomacy.md:8.2 and intel.md specifications

import std/[tables, options, strformat]
import ../types/[core, game_state, intel, espionage]

proc generateEspionageIntelligence*(
    state: var GameState, result: EspionageResult, turn: int32
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

  let actionName =
    case result.action
    of EspionageAction.TechTheft: "Tech Theft"
    of EspionageAction.SabotageLow: "Low-Impact Sabotage"
    of EspionageAction.SabotageHigh: "High-Impact Sabotage"
    of EspionageAction.Assassination: "Assassination"
    of EspionageAction.CyberAttack: "Cyber Attack"
    of EspionageAction.EconomicManipulation: "Economic Manipulation"
    of EspionageAction.PsyopsCampaign: "Psyops Campaign"
    of EspionageAction.CounterIntelSweep: "Counter-Intelligence Sweep"
    of EspionageAction.IntelligenceTheft: "Intelligence Theft"
    of EspionageAction.PlantDisinformation: "Plant Disinformation"

  if result.success:
    # Successful espionage - attacker receives intelligence on success
    let attackerDescription =
      case result.action
      of EspionageAction.TechTheft:
        &"ESPIONAGE SUCCESS: Tech theft from {result.target} - stole {result.srpStolen} SRP"
      of EspionageAction.SabotageLow, EspionageAction.SabotageHigh:
        &"ESPIONAGE SUCCESS: Sabotage of {result.target} - destroyed {result.iuDamage} IU"
      of EspionageAction.Assassination:
        &"ESPIONAGE SUCCESS: Assassination in {result.target} - key figure eliminated, -50% SRP gain for 1 turn"
      of EspionageAction.CyberAttack:
        &"ESPIONAGE SUCCESS: Cyber attack on {result.target} starbase - systems crippled"
      of EspionageAction.EconomicManipulation:
        &"ESPIONAGE SUCCESS: Economic manipulation of {result.target} - halved NCV for 1 turn"
      of EspionageAction.PsyopsCampaign:
        &"ESPIONAGE SUCCESS: Psyops campaign against {result.target} - -25% tax revenue for 1 turn"
      of EspionageAction.CounterIntelSweep:
        &"COUNTER-INTEL SUCCESS: Intelligence secured - enemy intel gathering blocked for 1 turn"
      of EspionageAction.IntelligenceTheft:
        &"ESPIONAGE SUCCESS: Intelligence theft from {result.target} - entire database stolen"
      of EspionageAction.PlantDisinformation:
        &"ESPIONAGE SUCCESS: Disinformation planted in {result.target}'s intelligence - corruption lasts 2 turns"

    let significance: int32 = 8 # Successful espionage is highly significant

    let attackerReport = ScoutEncounterReport(
      reportId: &"{result.attacker}-espionage-success-{turn}-{result.target}",
      fleetId: FleetId(0), # Intelligence operative, not fleet-specific
      turn: turn,
      systemId: SystemId(0), # Not system-specific (except sabotage/cyber)
      encounterType: ScoutEncounterType.DiplomaticActivity, # Covert operations
      observedHouses: @[result.target],
      observedFleetIds: @[],
      colonyId: none(ColonyId),
      fleetMovements: @[],
      description: attackerDescription,
      significance: significance,
    )

    # Write to intelligence database (Table read-modify-write)
    if state.intelligence.contains(result.attacker):
      var intel = state.intelligence[result.attacker]
      intel.scoutEncounters.add(attackerReport)
      state.intelligence[result.attacker] = intel

    # If NOT detected, target remains unaware (no intelligence report)
    # This is intentional - undetected espionage is covert

  if result.detected:
    # Failed/detected espionage - target receives intelligence on the attempt
    let targetDescription =
      if result.success:
        # Detected but successful (rare - target knows they were hit)
        &"ESPIONAGE DETECTED: {result.attacker} conducted {actionName} against your house. Operation succeeded despite detection."
      else:
        # Detected and failed (common)
        &"ESPIONAGE DETECTED: {result.attacker} attempted {actionName} against your house. Operation thwarted by counter-intelligence."

    let targetSignificance: int32 = if result.success: 9 else: 7
      # Higher if they succeeded despite detection

    let targetReport = ScoutEncounterReport(
      reportId: &"{result.target}-espionage-detected-{turn}-{result.attacker}",
      fleetId: FleetId(0), # Counter-intelligence, not fleet-specific
      turn: turn,
      systemId: SystemId(0),
      encounterType: ScoutEncounterType.DiplomaticActivity,
      observedHouses: @[result.attacker],
      observedFleetIds: @[],
      colonyId: none(ColonyId),
      fleetMovements: @[],
      description: targetDescription,
      significance: targetSignificance,
    )

    # Add to espionage activity log (per intel.md:types.nim EspionageActivityReport)
    let activityReport = EspionageActivityReport(
      turn: turn,
      perpetrator: result.attacker,
      action: actionName,
      targetSystem: none(SystemId),
        # Future: Track system for sabotage/cyber attacks when implemented
      detected: true,
      description:
        if result.success:
          &"{result.attacker} successfully conducted {actionName} (detected)"
        else:
          &"{result.attacker} failed {actionName} attempt (detected and blocked)",
    )

    # Write to intelligence database (Table read-modify-write)
    if state.intelligence.contains(result.target):
      var intel = state.intelligence[result.target]
      intel.scoutEncounters.add(targetReport)
      intel.espionageActivity.add(activityReport)
      state.intelligence[result.target] = intel

    # If espionage was detected, attacker also knows they were detected
    if not result.success:
      let failureSignificance: int32 = 6 # Failed espionage is moderately significant (prestige loss)

      let attackerFailureReport = ScoutEncounterReport(
        reportId: &"{result.attacker}-espionage-failed-{turn}-{result.target}",
        fleetId: FleetId(0), # Intelligence operative, not fleet-specific
        turn: turn,
        systemId: SystemId(0),
        encounterType: ScoutEncounterType.DiplomaticActivity,
        observedHouses: @[result.target],
        observedFleetIds: @[],
        colonyId: none(ColonyId),
        fleetMovements: @[],
        description:
          &"ESPIONAGE FAILED: {actionName} against {result.target} was detected and blocked by counter-intelligence.",
        significance: failureSignificance,
      )

      # Write to intelligence database (Table read-modify-write)
      if state.intelligence.contains(result.attacker):
        var intel = state.intelligence[result.attacker]
        intel.scoutEncounters.add(attackerFailureReport)
        state.intelligence[result.attacker] = intel
