## Database writer implementation (DoD - behavior on data)
##
## Insert operations for all database tables.
## Follows DRY principle with factory functions for each table.

import std/[json, times, strformat, logging, options, strutils]
import db_connector/db_sqlite
import ../types/telemetry  # DiagnosticMetrics
import ../types/[game_state, event]

const ENGINE_VERSION = "0.1.0"  # TODO: Get from build system

proc insertGame*(db: DbConn, seed: int64, numPlayers, maxTurns,
                 mapRings: int32, strategies: seq[string]): int64 =
  ## Insert game metadata (DRY - factory function)
  ## Returns game_id
  let strategiesJson = $(%strategies)  # JSON encode array
  db.exec(sql"""
    INSERT INTO games (
      game_id, timestamp, num_players, max_turns,
      actual_turns, map_rings, strategies, victor,
      victory_type, engine_version
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  """, $seed, $now(), $numPlayers, $maxTurns,
       "0",  # Updated after game complete
       $mapRings, strategiesJson, "", "", ENGINE_VERSION)
  debug &"Inserted game metadata for seed {seed}"
  return seed

proc updateGameResult*(db: DbConn, gameId: int64, actualTurns: int32,
                       victor: string = "", victoryType: string = "") =
  ## Update game metadata at completion
  db.exec(sql"""
    UPDATE games
    SET actual_turns = ?, victor = ?, victory_type = ?
    WHERE game_id = ?
  """, $actualTurns, victor, victoryType, $gameId)
  debug &"Updated game {gameId} result: {actualTurns} turns, victor={victor}"

proc insertDiagnosticRow*(db: DbConn, gameId: int64,
                          metrics: DiagnosticMetrics) =
  ## Insert diagnostics row (DRY - mirrors csv_writer column order)
  ## Maps DiagnosticMetrics fields to database columns

  # Convert boolean fields to integers (SQLite doesn't have native boolean)
  let dishonoredInt = if metrics.dishonoredStatusActive: 1 else: 0
  let treasuryDeficitInt = if metrics.treasuryDeficit: 1 else: 0
  let taxPenaltyInt = if metrics.taxPenaltyActive: 1 else: 0
  let autopilotInt = if metrics.autopilotActive: 1 else: 0
  let defCollapseInt = if metrics.defensiveCollapseActive: 1 else: 0
  let fighterViolationInt = if metrics.fighterCapacityViolation: 1 else: 0
  let squadronViolationInt = if metrics.squadronLimitViolation: 1 else: 0
  let clkNoRaidersInt = if metrics.clkResearchedNoRaiders: 1 else: 0
  let goapEnabledInt = if metrics.goapEnabled: 1 else: 0

  # Convert strategy enum to string
  let strategyStr = $metrics.strategy

  db.exec(sql"""
    INSERT INTO diagnostics (
      game_id, turn, act, rank, house_id, strategy,
      total_systems_on_map, treasury, production, pu_growth,
      zero_spend_turns, gco, nhv, tax_rate,
      total_iu, total_pu, total_ptu, pop_growth_rate,
      tech_cst, tech_wep, tech_el, tech_sl, tech_ter,
      tech_eli, tech_clk, tech_sld, tech_cic, tech_fd, tech_aco,
      research_erp, research_srp, research_trp, research_breakthroughs,
      research_wasted_erp, research_wasted_srp,
      turns_at_max_el, turns_at_max_sl,
      maintenance_cost, maintenance_shortfall_turns,
      prestige, prestige_change, prestige_victory_progress,
      combat_cer_avg, bombard_rounds, ground_victories, retreats,
      crit_hits_dealt, crit_hits_received,
      cloaked_ambush, shields_activated,
      ally_count, hostile_count, enemy_count, neutral_count,
      pact_violations, dishonored, diplo_isolation_turns,
      pact_formations, pact_breaks,
      hostility_declarations, war_declarations,
      espionage_success, espionage_failure, espionage_detected,
      tech_thefts, sabotage_ops, assassinations, cyber_attacks,
      ebp_spent, cip_spent, counter_intel_success,
      pop_transfers_active, pop_transfers_done, pop_transfers_lost,
      ptu_transferred, blockaded_colonies, blockade_turns_total,
      treasury_deficit, infra_damage, salvage_recovered,
      maintenance_deficit, tax_penalty_active, avg_tax_6turn,
      fighter_cap_max, fighter_cap_used, fighter_violation,
      squadron_limit_max, squadron_limit_used, squadron_violation,
      starbases_actual, autopilot, defensive_collapse,
      turns_to_elimination, missed_orders,
      space_wins, space_losses, space_total,
      orbital_failures, orbital_total,
      raider_success, raider_attempts, raider_detected,
      raider_stealth_success,
      eli_attempts, avg_eli_roll, avg_clk_roll,
      scouts_detected, scouts_detected_by,
      capacity_violations, fighters_disbanded,
      total_fighters, idle_carriers, total_carriers, total_transports,
      fighter_ships, corvette_ships, frigate_ships, scout_ships,
      raider_ships, destroyer_ships, cruiser_ships, light_cruiser_ships,
      heavy_cruiser_ships, battlecruiser_ships, battleship_ships,
      dreadnought_ships, super_dreadnought_ships,
      carrier_ships, super_carrier_ships,
      etac_ships, troop_transport_ships, planet_breaker_ships,
      total_ships,
      planetary_shield_units, ground_battery_units, army_units,
      marines_at_colonies, marines_on_transports, marine_division_units,
      total_spaceports, total_shipyards, total_drydocks,
      total_invasions, vulnerable_targets_count,
      invasion_orders_generated, invasion_orders_bombard,
      invasion_orders_invade, invasion_orders_blitz,
      invasion_orders_canceled,
      invasion_attempts_total, invasion_attempts_successful,
      invasion_attempts_failed, invasion_orders_rejected,
      blitz_attempts_total, blitz_attempts_successful,
      blitz_attempts_failed,
      bombardment_attempts_total, bombardment_orders_failed,
      invasion_marines_killed, invasion_defenders_killed,
      colonize_orders_generated,
      active_campaigns_total, active_campaigns_scouting,
      active_campaigns_bombardment, active_campaigns_invasion,
      campaigns_completed_success, campaigns_abandoned_stalled,
      campaigns_abandoned_captured, campaigns_abandoned_timeout,
      clk_no_raiders, scout_count,
      spy_planet, hack_starbase, total_espionage,
      undefended_colonies, total_colonies,
      mothball_used, mothball_total,
      invalid_orders, total_orders,
      domestikos_budget_allocated, logothete_budget_allocated,
      drungarius_budget_allocated, eparch_budget_allocated,
      build_orders_generated, pp_spent_construction,
      domestikos_requirements_total, domestikos_requirements_fulfilled,
      domestikos_requirements_unfulfilled, domestikos_requirements_deferred,
      colonies_lost, colonies_gained,
      colonies_gained_via_colonization, colonies_gained_via_conquest,
      ships_lost, ships_gained, fighters_lost, fighters_gained,
      bilateral_relations,
      events_order_completed, events_order_failed, events_order_rejected,
      events_combat_total, events_bombardment, events_colony_captured,
      events_espionage_total, events_diplomatic_total,
      events_research_total, events_colony_total,
      advisor_reasoning,
      goap_enabled, goap_plans_active, goap_plans_completed,
      goap_goals_extracted, goap_planning_time_ms,
      goap_invasion_goals, goap_invasion_plans,
      goap_actions_executed, goap_actions_failed
    ) VALUES (
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?
    )
  """,
    $gameId, $metrics.turn, $metrics.act, $metrics.rank,
    $metrics.houseId, strategyStr,
    $metrics.totalSystemsOnMap, $metrics.treasuryBalance,
    $metrics.productionPerTurn, $metrics.puGrowth,
    $metrics.zeroSpendTurns, $metrics.grossColonyOutput,
    $metrics.netHouseValue, $metrics.taxRate,
    $metrics.totalIndustrialUnits, $metrics.totalPopulationUnits,
    $metrics.totalPopulationPTU, $metrics.populationGrowthRate,
    $metrics.techCST, $metrics.techWEP, $metrics.techEL, $metrics.techSL,
    $metrics.techTER, $metrics.techELI, $metrics.techCLK, $metrics.techSLD,
    $metrics.techCIC, $metrics.techFD, $metrics.techACO,
    $metrics.researchERP, $metrics.researchSRP, $metrics.researchTRP,
    $metrics.researchBreakthroughs,
    $metrics.researchWastedERP, $metrics.researchWastedSRP,
    $metrics.turnsAtMaxEL, $metrics.turnsAtMaxSL,
    $metrics.maintenanceCostTotal, $metrics.maintenanceShortfallTurns,
    $metrics.prestigeCurrent, $metrics.prestigeChange,
    $metrics.prestigeVictoryProgress,
    $metrics.combatCERAverage, $metrics.bombardmentRoundsTotal,
    $metrics.groundCombatVictories, $metrics.retreatsExecuted,
    $metrics.criticalHitsDealt, $metrics.criticalHitsReceived,
    $metrics.cloakedAmbushSuccess, $metrics.shieldsActivatedCount,
    $metrics.allyStatusCount, $metrics.hostileStatusCount,
    $metrics.enemyStatusCount, $metrics.neutralStatusCount,
    $metrics.pactViolationsTotal, dishonoredInt,
    $metrics.diplomaticIsolationTurns,
    $metrics.pactFormationsTotal, $metrics.pactBreaksTotal,
    $metrics.hostilityDeclarationsTotal, $metrics.warDeclarationsTotal,
    $metrics.espionageSuccessCount, $metrics.espionageFailureCount,
    $metrics.espionageDetectedCount,
    $metrics.techTheftsSuccessful, $metrics.sabotageOperations,
    $metrics.assassinationAttempts, $metrics.cyberAttacksLaunched,
    $metrics.ebpPointsSpent, $metrics.cipPointsSpent,
    $metrics.counterIntelSuccesses,
    $metrics.populationTransfersActive, $metrics.populationTransfersCompleted,
    $metrics.populationTransfersLost,
    $metrics.ptuTransferredTotal, $metrics.coloniesBlockadedCount,
    $metrics.blockadeTurnsCumulative,
    treasuryDeficitInt, $metrics.infrastructureDamageTotal,
    $metrics.salvageValueRecovered,
    $metrics.maintenanceCostDeficit, taxPenaltyInt, $metrics.avgTaxRate6Turn,
    $metrics.fighterCapacityMax, $metrics.fighterCapacityUsed,
    fighterViolationInt,
    $metrics.squadronLimitMax, $metrics.squadronLimitUsed,
    squadronViolationInt,
    $metrics.starbasesActual, autopilotInt, defCollapseInt,
    $metrics.turnsUntilElimination, $metrics.missedOrderTurns,
    $metrics.spaceCombatWins, $metrics.spaceCombatLosses,
    $metrics.spaceCombatTotal,
    $metrics.orbitalFailures, $metrics.orbitalTotal,
    $metrics.raiderAmbushSuccess, $metrics.raiderAmbushAttempts,
    $metrics.raiderDetectedCount,
    $metrics.raiderStealthSuccessCount,
    $metrics.eliDetectionAttempts, $metrics.avgEliRoll, $metrics.avgClkRoll,
    $metrics.scoutsDetected, $metrics.scoutsDetectedBy,
    $metrics.capacityViolationsActive, $metrics.fightersDisbanded,
    $metrics.totalFighters, $metrics.idleCarriers, $metrics.totalCarriers,
    $metrics.totalTransports,
    $metrics.fighterShips, $metrics.corvetteShips, $metrics.frigateShips,
    $metrics.scoutShips,
    $metrics.raiderShips, $metrics.destroyerShips, $metrics.cruiserShips,
    $metrics.lightCruiserShips,
    $metrics.heavyCruiserShips, $metrics.battlecruiserShips,
    $metrics.battleshipShips,
    $metrics.dreadnoughtShips, $metrics.superDreadnoughtShips,
    $metrics.carrierShips, $metrics.superCarrierShips,
    $metrics.etacShips, $metrics.troopTransportShips,
    $metrics.planetBreakerShips,
    $metrics.totalShips,
    $metrics.planetaryShieldUnits, $metrics.groundBatteryUnits,
    $metrics.armyUnits,
    $metrics.marinesAtColonies, $metrics.marinesOnTransports,
    $metrics.marineDivisionUnits,
    $metrics.totalSpaceports, $metrics.totalShipyards, $metrics.totalDrydocks,
    $metrics.totalInvasions, $metrics.vulnerableTargets_count,
    $metrics.invasionOrders_generated, $metrics.invasionOrders_bombard,
    $metrics.invasionOrders_invade, $metrics.invasionOrders_blitz,
    $metrics.invasionOrders_canceled,
    $metrics.invasionAttemptsTotal, $metrics.invasionAttemptsSuccessful,
    $metrics.invasionAttemptsFailed, $metrics.invasionOrdersRejected,
    $metrics.blitzAttemptsTotal, $metrics.blitzAttemptsSuccessful,
    $metrics.blitzAttemptsFailed,
    $metrics.bombardmentAttemptsTotal, $metrics.bombardmentOrdersFailed,
    $metrics.invasionMarinesKilled, $metrics.invasionDefendersKilled,
    $metrics.colonizeOrdersSubmitted,
    $metrics.activeCampaigns_total, $metrics.activeCampaigns_scouting,
    $metrics.activeCampaigns_bombardment, $metrics.activeCampaigns_invasion,
    $metrics.campaigns_completed_success, $metrics.campaigns_abandoned_stalled,
    $metrics.campaigns_abandoned_captured, $metrics.campaigns_abandoned_timeout,
    clkNoRaidersInt, $metrics.scoutCount,
    $metrics.spyPlanetMissions, $metrics.hackStarbaseMissions,
    $metrics.totalEspionageMissions,
    $metrics.coloniesWithoutDefense, $metrics.totalColonies,
    $metrics.mothballedFleetsUsed, $metrics.mothballedFleetsTotal,
    $metrics.invalidOrders, $metrics.totalOrders,
    $metrics.domestikosBudgetAllocated, $metrics.logotheteBudgetAllocated,
    $metrics.drungariusBudgetAllocated, $metrics.eparchBudgetAllocated,
    $metrics.buildOrdersGenerated, $metrics.ppSpentConstruction,
    $metrics.domestikosRequirementsTotal,
    $metrics.domestikosRequirementsFulfilled,
    $metrics.domestikosRequirementsUnfulfilled,
    $metrics.domestikosRequirementsDeferred,
    $metrics.coloniesLost, $metrics.coloniesGained,
    $metrics.coloniesGainedViaColonization, $metrics.coloniesGainedViaConquest,
    $metrics.shipsLost, $metrics.shipsGained,
    $metrics.fightersLost, $metrics.fightersGained,
    $metrics.bilateralRelations,
    $metrics.eventsOrderCompleted, $metrics.eventsOrderFailed,
    $metrics.eventsOrderRejected,
    $metrics.eventsCombatTotal, $metrics.eventsBombardment,
    $metrics.eventsColonyCaptured,
    $metrics.eventsEspionageTotal, $metrics.eventsDiplomaticTotal,
    $metrics.eventsResearchTotal, $metrics.eventsColonyTotal,
    metrics.advisorReasoning,
    goapEnabledInt, $metrics.goapPlansActive, $metrics.goapPlansCompleted,
    $metrics.goapGoalsExtracted, $metrics.goapPlanningTimeMs,
    $metrics.goapInvasionGoals, $metrics.goapInvasionPlans,
    $metrics.goapActionsExecuted, $metrics.goapActionsFailed
  )

proc insertGameEvent*(db: DbConn, gameId: int64, turn: int32,
                      event: GameEvent) =
  ## Insert game event (DRY - factory for all event types)
  ## Maps GameEvent to flat database row

  # Extract optional fields
  let houseIdStr = if event.houseId.isSome: $event.houseId.get else: ""
  let fleetIdStr = if event.fleetId.isSome: event.fleetId.get else: ""
  let systemIdVal = if event.systemId.isSome: $event.systemId.get else: "0"

  # orderType only exists for order-related events (case object variant)
  let orderTypeStr =
    case event.eventType
    of GameEventType.OrderIssued, GameEventType.OrderCompleted,
       GameEventType.OrderRejected, GameEventType.OrderFailed,
       GameEventType.OrderAborted, GameEventType.FleetArrived:
      if event.orderType.isSome: event.orderType.get else: ""
    else:
      ""

  # reason only exists for order-related events
  let reasonStr =
    case event.eventType
    of GameEventType.OrderIssued, GameEventType.OrderCompleted,
       GameEventType.OrderRejected, GameEventType.OrderFailed,
       GameEventType.OrderAborted, GameEventType.FleetArrived:
      if event.reason.isSome: event.reason.get else: ""
    else:
      ""

  # Serialize event-specific data as JSON (if needed)
  let eventDataJson = "{}"  # TODO: Implement serializeEventData()

  db.exec(sql"""
    INSERT INTO game_events (
      game_id, turn, event_type, house_id, fleet_id, system_id,
      order_type, description, reason, event_data
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  """,
    $gameId, $turn, $event.eventType,
    houseIdStr, fleetIdStr, systemIdVal,
    orderTypeStr, event.description, reasonStr, eventDataJson
  )

proc insertFleetSnapshot*(db: DbConn, gameId: int64, turn: int32,
                         fleetId: string, houseId: string,
                         locationSystem: int32,
                         orderType: string, orderTarget: int32,
                         hasArrived: bool,
                         shipsTotal, etacCount, scoutCount,
                         combatShips, transportCount,
                         idleTurnsCombat, idleTurnsScout,
                         idleTurnsEtac, idleTurnsTransport: int32) =
  ## Insert fleet tracking snapshot (DoD - direct field mapping)
  ## Called per-turn for each fleet in the game
  let arrivedInt = if hasArrived: "1" else: "0"
  let orderTypeVal = if orderType == "": "" else: orderType
  # 0 or negative = no target (NULL in database)
  let orderTargetVal = if orderTarget <= 0: "" else: $orderTarget

  db.exec(sql"""
    INSERT INTO fleet_tracking (
      game_id, turn, fleet_id, house_id, location_system_id,
      active_order_type, order_target_system_id, has_arrived,
      ships_total, etac_count, scout_count, combat_ships,
      troop_transport_count,
      idle_turns_combat, idle_turns_scout, idle_turns_etac,
      idle_turns_transport
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  """,
    $gameId, $turn, fleetId, houseId, $locationSystem,
    orderTypeVal, orderTargetVal, arrivedInt,
    $shipsTotal, $etacCount, $scoutCount, $combatShips,
    $transportCount,
    $idleTurnsCombat, $idleTurnsScout, $idleTurnsEtac,
    $idleTurnsTransport
  )

proc insertGameState*(db: DbConn, gameId: int64, turn: int32,
                      stateJson: string) =
  ## Insert full GameState snapshot as JSON (optional)
  ## Only used if DBConfig.enableGameStates is true
  db.exec(sql"""
    INSERT INTO game_states (game_id, turn, state_json)
    VALUES (?, ?, ?)
  """, $gameId, $turn, stateJson)
  debug &"Inserted GameState snapshot for turn {turn}"
