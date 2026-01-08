## Per-Game Database Writer
##
## Unified persistence layer for per-game databases.
## Each game has its own database at data/games/{uuid}/ec4x.db
##
## Architecture:
## - Schema created by initPerGameDatabase() in init/engine.nim
## - This module only handles INSERT operations
## - No table creation (schema.nim owns that)
## - Uses GameState.dbPath for database location
##
## DRY Principle: Single implementation for each entity type
## DoD Principle: Pure functions operating on GameState data

import std/[options, strutils]
import db_connector/db_sqlite
import ../../common/logger
import ../types/[telemetry, event, game_state]

# ============================================================================
# Core State Writers
# ============================================================================

proc updateGameMetadata*(state: GameState) =
  ## Update games table with current turn/phase info
  ## Called after each turn resolution
  let db = open(state.dbPath, "", "", "")
  defer: db.close()

  db.exec(
    sql"""
    UPDATE games
    SET turn = ?, phase = ?, updated_at = unixepoch()
    WHERE id = ?
  """,
    $state.turn,
    $state.phase,
    state.gameId,
  )

proc saveDiagnosticMetrics*(state: GameState, metrics: DiagnosticMetrics) =
  ## Insert diagnostic metrics row for a house this turn
  ## Called per-house per-turn during telemetry collection
  let db = open(state.dbPath, "", "", "")
  defer: db.close()

  # Convert boolean fields to integers (SQLite convention)
  let dishonoredInt = if metrics.dishonoredStatusActive: 1 else: 0
  let treasuryDeficitInt = if metrics.treasuryDeficit: 1 else: 0
  let taxPenaltyInt = if metrics.taxPenaltyActive: 1 else: 0
  let autopilotInt = if metrics.autopilotActive: 1 else: 0
  let defCollapseInt = if metrics.defensiveCollapseActive: 1 else: 0
  let fighterViolationInt = if metrics.fighterCapacityViolation: 1 else: 0
  let squadronViolationInt = if metrics.squadronLimitViolation: 1 else: 0
  let clkNoRaidersInt = if metrics.clkResearchedNoRaiders: 1 else: 0

  db.exec(
    sql"""
    INSERT INTO diagnostic_metrics (
      game_id, turn, act, rank, house_id,
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
      raider_ships, destroyer_ships, light_cruiser_ships,
      cruiser_ships, battlecruiser_ships, battleship_ships,
      dreadnought_ships, super_dreadnought_ships,
      carrier_ships, super_carrier_ships,
      etac_ships, troop_transport_ships, planet_breaker_ships,
      total_ships,
      planetary_shield_units, ground_battery_units, army_units,
      marines_at_colonies, marines_on_transports, marine_division_units,
      total_spaceports, total_shipyards, total_drydocks,
      total_invasions, vulnerable_targets_count,
      invasion_commands_generated, invasion_orders_bombard,
      invasion_orders_invade, invasion_orders_blitz,
      invasion_orders_canceled,
      invasion_attempts_total, invasion_attempts_successful,
      invasion_attempts_failed, invasion_orders_rejected,
      blitz_attempts_total, blitz_attempts_successful,
      blitz_attempts_failed,
      bombardment_attempts_total, bombardment_orders_failed,
      invasion_marines_killed, invasion_defenders_killed,
      colonize_commands_generated,
      active_campaigns_total, active_campaigns_scouting,
      active_campaigns_bombardment, active_campaigns_invasion,
      campaigns_completed_success, campaigns_abandoned_stalled,
      campaigns_abandoned_captured, campaigns_abandoned_timeout,
      clk_no_raiders, scout_count,
      spy_planet, hack_starbase, total_espionage,
      undefended_colonies, total_colonies,
      mothball_used, mothball_total,
      invalid_orders, total_commands,
      domestikos_budget, logothete_budget, drungarius_budget, eparch_budget,
      build_commands_generated, pp_spent_construction,
      domestikos_requirements_total, domestikos_requirements_fulfilled,
      domestikos_requirements_unfulfilled, domestikos_requirements_deferred,
      total_build_queue_depth, etac_in_construction,
      ships_under_construction, buildings_under_construction,
      ships_commissioned_this_turn, etac_commissioned_this_turn,
      squadrons_commissioned_this_turn,
      fleets_moved, systems_colonized, failed_colonization_attempts,
      fleets_with_orders, stuck_fleets,
      total_etacs, etacs_without_orders, etacs_in_transit,
      colonies_lost, colonies_gained,
      colonies_gained_via_colonization, colonies_gained_via_conquest,
      ships_lost, ships_gained, fighters_lost, fighters_gained,
      bilateral_relations,
      events_order_completed, events_order_failed, events_order_rejected,
      events_combat_total, events_bombardment, events_colony_captured,
      events_espionage_total, events_diplomatic_total,
      events_research_total, events_colony_total,
      upkeep_pct_income, gco_per_pu, construction_pct_income,
      force_projection, fleet_readiness, econ_damage_efficiency,
      capital_ship_ratio,
      avg_war_duration, relationship_volatility,
      avg_colony_development, border_friction
    ) VALUES (
      ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?,
      ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
      ?, ?, ?, ?,
      ?, ?, ?, ?,
      ?, ?,
      ?, ?
    )
  """,
    state.gameId,
    $metrics.turn,
    $metrics.act,
    $metrics.rank,
    $metrics.houseId.uint32,
    $metrics.totalSystemsOnMap,
    $metrics.treasuryBalance,
    $metrics.productionPerTurn,
    $metrics.puGrowth,
    $metrics.zeroSpendTurns,
    $metrics.grossColonyOutput,
    $metrics.netHouseValue,
    $metrics.taxRate,
    $metrics.totalIndustrialUnits,
    $metrics.totalPopulationUnits,
    $metrics.totalPopulationPTU,
    $metrics.populationGrowthRate,
    $metrics.techCST,
    $metrics.techWEP,
    $metrics.techEL,
    $metrics.techSL,
    $metrics.techTER,
    $metrics.techELI,
    $metrics.techCLK,
    $metrics.techSLD,
    $metrics.techCIC,
    $metrics.techFD,
    $metrics.techACO,
    $metrics.researchERP,
    $metrics.researchSRP,
    $metrics.researchTRP,
    $metrics.researchBreakthroughs,
    $metrics.researchWastedERP,
    $metrics.researchWastedSRP,
    $metrics.turnsAtMaxEL,
    $metrics.turnsAtMaxSL,
    $metrics.maintenanceCostTotal,
    $metrics.maintenanceShortfallTurns,
    $metrics.prestigeCurrent,
    $metrics.prestigeChange,
    $metrics.prestigeVictoryProgress,
    $metrics.combatCERAverage,
    $metrics.bombardmentRoundsTotal,
    $metrics.groundCombatVictories,
    $metrics.retreatsExecuted,
    $metrics.criticalHitsDealt,
    $metrics.criticalHitsReceived,
    $metrics.cloakedAmbushSuccess,
    $metrics.shieldsActivatedCount,
    $metrics.allyStatusCount,
    $metrics.hostileStatusCount,
    $metrics.enemyStatusCount,
    $metrics.neutralStatusCount,
    $metrics.pactViolationsTotal,
    dishonoredInt,
    $metrics.diplomaticIsolationTurns,
    $metrics.pactFormationsTotal,
    $metrics.pactBreaksTotal,
    $metrics.hostilityDeclarationsTotal,
    $metrics.warDeclarationsTotal,
    $metrics.espionageSuccessCount,
    $metrics.espionageFailureCount,
    $metrics.espionageDetectedCount,
    $metrics.techTheftsSuccessful,
    $metrics.sabotageOperations,
    $metrics.assassinationAttempts,
    $metrics.cyberAttacksLaunched,
    $metrics.ebpPointsSpent,
    $metrics.cipPointsSpent,
    $metrics.counterIntelSuccesses,
    $metrics.populationTransfersActive,
    $metrics.populationTransfersCompleted,
    $metrics.populationTransfersLost,
    $metrics.ptuTransferredTotal,
    $metrics.coloniesBlockadedCount,
    $metrics.blockadeTurnsCumulative,
    treasuryDeficitInt,
    $metrics.infrastructureDamageTotal,
    $metrics.salvageValueRecovered,
    $metrics.maintenanceCostDeficit,
    taxPenaltyInt,
    $metrics.avgTaxRate6Turn,
    $metrics.fighterCapacityMax,
    $metrics.fighterCapacityUsed,
    fighterViolationInt,
    $metrics.squadronLimitMax,
    $metrics.squadronLimitUsed,
    squadronViolationInt,
    $metrics.starbasesActual,
    autopilotInt,
    defCollapseInt,
    $metrics.turnsUntilElimination,
    $metrics.missedOrderTurns,
    $metrics.spaceCombatWins,
    $metrics.spaceCombatLosses,
    $metrics.spaceCombatTotal,
    $metrics.orbitalFailures,
    $metrics.orbitalTotal,
    $metrics.raiderAmbushSuccess,
    $metrics.raiderAmbushAttempts,
    $metrics.raiderDetectedCount,
    $metrics.raiderStealthSuccessCount,
    $metrics.eliDetectionAttempts,
    $metrics.avgEliRoll,
    $metrics.avgClkRoll,
    $metrics.scoutsDetected,
    $metrics.scoutsDetectedBy,
    $metrics.capacityViolationsActive,
    $metrics.fightersDisbanded,
    $metrics.totalFighters,
    $metrics.idleCarriers,
    $metrics.totalCarriers,
    $metrics.totalTransports,
    $metrics.fighterShips,
    $metrics.corvetteShips,
    $metrics.frigateShips,
    $metrics.scoutShips,
    $metrics.raiderShips,
    $metrics.destroyerShips,
    $metrics.lightCruiserShips,
    $metrics.cruiserShips,
    $metrics.battlecruiserShips,
    $metrics.battleshipShips,
    $metrics.dreadnoughtShips,
    $metrics.superDreadnoughtShips,
    $metrics.carrierShips,
    $metrics.superCarrierShips,
    $metrics.etacShips,
    $metrics.troopTransportShips,
    $metrics.planetBreakerShips,
    $metrics.totalShips,
    $metrics.planetaryShieldUnits,
    $metrics.groundBatteryUnits,
    $metrics.armyUnits,
    $metrics.marinesAtColonies,
    $metrics.marinesOnTransports,
    $metrics.marineDivisionUnits,
    $metrics.totalSpaceports,
    $metrics.totalShipyards,
    $metrics.totalDrydocks,
    $metrics.totalInvasions,
    $metrics.vulnerableTargets_count,
    $metrics.invasionOrders_generated,
    $metrics.invasionOrders_bombard,
    $metrics.invasionOrders_invade,
    $metrics.invasionOrders_blitz,
    $metrics.invasionOrders_canceled,
    $metrics.invasionAttemptsTotal,
    $metrics.invasionAttemptsSuccessful,
    $metrics.invasionAttemptsFailed,
    $metrics.invasionOrdersRejected,
    $metrics.blitzAttemptsTotal,
    $metrics.blitzAttemptsSuccessful,
    $metrics.blitzAttemptsFailed,
    $metrics.bombardmentAttemptsTotal,
    $metrics.bombardmentOrdersFailed,
    $metrics.invasionMarinesKilled,
    $metrics.invasionDefendersKilled,
    $metrics.colonizeOrdersSubmitted,
    $metrics.activeCampaigns_total,
    $metrics.activeCampaigns_scouting,
    $metrics.activeCampaigns_bombardment,
    $metrics.activeCampaigns_invasion,
    $metrics.campaigns_completed_success,
    $metrics.campaigns_abandoned_stalled,
    $metrics.campaigns_abandoned_captured,
    $metrics.campaigns_abandoned_timeout,
    clkNoRaidersInt,
    $metrics.scoutCount,
    $metrics.spyPlanetMissions,
    $metrics.hackStarbaseMissions,
    $metrics.totalEspionageMissions,
    $metrics.coloniesWithoutDefense,
    $metrics.totalColonies,
    $metrics.mothballedFleetsUsed,
    $metrics.mothballedFleetsTotal,
    $metrics.invalidOrders,
    $metrics.totalOrders,
    $metrics.domestikosBudgetAllocated,
    $metrics.logotheteBudgetAllocated,
    $metrics.drungariusBudgetAllocated,
    $metrics.eparchBudgetAllocated,
    $metrics.buildOrdersGenerated,
    $metrics.ppSpentConstruction,
    $metrics.domestikosRequirementsTotal,
    $metrics.domestikosRequirementsFulfilled,
    $metrics.domestikosRequirementsUnfulfilled,
    $metrics.domestikosRequirementsDeferred,
    $metrics.totalBuildQueueDepth,
    $metrics.etacInConstruction,
    $metrics.shipsUnderConstruction,
    $metrics.buildingsUnderConstruction,
    $metrics.shipsCommissionedThisTurn,
    $metrics.etacCommissionedThisTurn,
    $metrics.squadronsCommissionedThisTurn,
    $metrics.fleetsMoved,
    $metrics.systemsColonized,
    $metrics.failedColonizationAttempts,
    $metrics.fleetsWithOrders,
    $metrics.stuckFleets,
    $metrics.totalETACs,
    $metrics.etacsWithoutOrders,
    $metrics.etacsInTransit,
    $metrics.coloniesLost,
    $metrics.coloniesGained,
    $metrics.coloniesGainedViaColonization,
    $metrics.coloniesGainedViaConquest,
    $metrics.shipsLost,
    $metrics.shipsGained,
    $metrics.fightersLost,
    $metrics.fightersGained,
    metrics.bilateralRelations,
    $metrics.eventsOrderCompleted,
    $metrics.eventsOrderFailed,
    $metrics.eventsOrderRejected,
    $metrics.eventsCombatTotal,
    $metrics.eventsBombardment,
    $metrics.eventsColonyCaptured,
    $metrics.eventsEspionageTotal,
    $metrics.eventsDiplomaticTotal,
    $metrics.eventsResearchTotal,
    $metrics.eventsColonyTotal,
    $metrics.upkeepAsPercentageOfIncome,
    $metrics.gcoPerPopulationUnit,
    $metrics.constructionSpendingAsPercentageOfIncome,
    $metrics.forceProjection,
    $metrics.fleetReadiness,
    $metrics.economicDamageEfficiency,
    $metrics.capitalShipRatio,
    $metrics.averageWarDuration,
    $metrics.relationshipVolatility,
    $metrics.averageColonyDevelopment,
    $metrics.borderFriction,
  )

# ============================================================================
# Event Writers
# ============================================================================

proc saveGameEvent*(state: GameState, event: GameEvent) =
  ## Insert game event into per-game database
  ## Called during event processing
  let db = open(state.dbPath, "", "", "")
  defer: db.close()

  # Extract optional fields
  let houseIdStr = if event.houseId.isSome: $event.houseId.get().uint32 else: ""
  let fleetIdStr = if event.fleetId.isSome: $event.fleetId.get().uint32 else: ""
  let systemIdStr = if event.systemId.isSome: $event.systemId.get().uint32 else: ""

  # Serialize event-specific data as JSON (placeholder for now)
  let eventDataJson = "{}"

  db.exec(
    sql"""
    INSERT INTO game_events (
      game_id, turn, event_type, house_id, fleet_id, system_id,
      command_type, description, reason, event_data
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  """,
    state.gameId,
    $event.turn,
    $event.eventType,
    houseIdStr,
    fleetIdStr,
    systemIdStr,
    "", # commandType (extract from event if needed)
    event.description,
    "", # reason (extract from event if needed)
    eventDataJson,
  )

proc saveGameEvents*(state: GameState, events: seq[GameEvent]) =
  ## Batch insert game events (more efficient than individual inserts)
  ## Called after turn resolution
  if events.len == 0:
    return

  let db = open(state.dbPath, "", "", "")
  defer: db.close()

  db.exec(sql"BEGIN TRANSACTION")
  for event in events:
    let houseIdStr = if event.houseId.isSome: $event.houseId.get().uint32 else: ""
    let fleetIdStr = if event.fleetId.isSome: $event.fleetId.get().uint32 else: ""
    let systemIdStr = if event.systemId.isSome: $event.systemId.get().uint32 else: ""
    let eventDataJson = "{}"

    db.exec(
      sql"""
      INSERT INTO game_events (
        game_id, turn, event_type, house_id, fleet_id, system_id,
        command_type, description, reason, event_data
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
      state.gameId,
      $event.turn,
      $event.eventType,
      houseIdStr,
      fleetIdStr,
      systemIdStr,
      "",
      event.description,
      "",
      eventDataJson,
    )
  db.exec(sql"COMMIT")

  logDebug(
    "Persistence", "Saved game events", "count=", $events.len, " turn=", $state.turn
  )
