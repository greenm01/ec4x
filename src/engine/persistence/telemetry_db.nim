## @engine/persistence/telemetry_db.nim
##
## Handles SQLite persistence for telemetry data (DiagnosticMetrics).
import db_connector/db_sqlite
import ../types/telemetry # For DiagnosticMetrics

proc getTelemetryDbPath(): string =
  ## Returns the path to the telemetry SQLite database file.
  ## For now, hardcode to a file in the data directory.
  result = "data/telemetry.sqlite"

proc openTelemetryDb*(mode: FileMode = fmReadWrite): DbConn =
  ## Opens a connection to the telemetry SQLite database.
  result = open(getTelemetryDbPath(), "", "", "")

proc closeTelemetryDb*(db: DbConn) =
  ## Closes the connection to the telemetry SQLite database.
  db.close()

proc createDiagnosticMetricsTable*(db: DbConn) =
  ## Creates the diagnostic_metrics table if it doesn't exist.
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS diagnostic_metrics (
      game_id TEXT NOT NULL,
      turn INTEGER NOT NULL,
      act INTEGER NOT NULL,
      rank INTEGER NOT NULL,
      house_id INTEGER NOT NULL,
      total_systems_on_map INTEGER NOT NULL,

      -- Economy (Core)
      treasury_balance INTEGER NOT NULL,
      production_per_turn INTEGER NOT NULL,
      pu_growth INTEGER NOT NULL,
      zero_spend_turns INTEGER NOT NULL,
      gross_colony_output INTEGER NOT NULL,
      net_house_value INTEGER NOT NULL,
      tax_rate INTEGER NOT NULL,
      total_industrial_units INTEGER NOT NULL,
      total_population_units INTEGER NOT NULL,
      total_population_ptu INTEGER NOT NULL,
      population_growth_rate INTEGER NOT NULL,

      -- Tech Levels (All 11 technology types)
      tech_cst INTEGER NOT NULL,
      tech_wep INTEGER NOT NULL,
      tech_el INTEGER NOT NULL,
      tech_sl INTEGER NOT NULL,
      tech_ter INTEGER NOT NULL,
      tech_eli INTEGER NOT NULL,
      tech_clk INTEGER NOT NULL,
      tech_sld INTEGER NOT NULL,
      tech_cic INTEGER NOT NULL,
      tech_fd INTEGER NOT NULL,
      tech_aco INTEGER NOT NULL,

      -- Research Points (Accumulated this turn)
      research_erp INTEGER NOT NULL,
      research_srp INTEGER NOT NULL,
      research_trp INTEGER NOT NULL,
      research_breakthroughs INTEGER NOT NULL,

      -- Research Waste Tracking (Tech Level Caps)
      research_wasted_erp INTEGER NOT NULL,
      research_wasted_srp INTEGER NOT NULL,
      turns_at_max_el INTEGER NOT NULL,
      turns_at_max_sl INTEGER NOT NULL,

      -- Maintenance & Prestige
      maintenance_cost_total INTEGER NOT NULL,
      maintenance_shortfall_turns INTEGER NOT NULL,
      prestige_current INTEGER NOT NULL,
      prestige_change INTEGER NOT NULL,
      prestige_victory_progress INTEGER NOT NULL,

      -- Combat Performance (from combat.toml)
      combat_cer_average INTEGER NOT NULL,
      bombardment_rounds_total INTEGER NOT NULL,
      ground_combat_victories INTEGER NOT NULL,
      retreats_executed INTEGER NOT NULL,
      critical_hits_dealt INTEGER NOT NULL,
      critical_hits_received INTEGER NOT NULL,
      cloaked_ambush_success INTEGER NOT NULL,
      shields_activated_count INTEGER NOT NULL,

      -- Diplomatic Status (4-level system: Neutral, Ally, Hostile, Enemy)
      ally_status_count INTEGER NOT NULL,
      hostile_status_count INTEGER NOT NULL,
      enemy_status_count INTEGER NOT NULL,
      neutral_status_count INTEGER NOT NULL,
      pact_violations_total INTEGER NOT NULL,
      dishonored_status_active INTEGER NOT NULL, -- Bool as 0 or 1
      diplomatic_isolation_turns INTEGER NOT NULL,

      -- Treaty Activity Metrics
      pact_formations_total INTEGER NOT NULL,
      pact_breaks_total INTEGER NOT NULL,
      hostility_declarations_total INTEGER NOT NULL,
      war_declarations_total INTEGER NOT NULL,

      -- Espionage Activity (from espionage.toml)
      espionage_success_count INTEGER NOT NULL,
      espionage_failure_count INTEGER NOT NULL,
      espionage_detected_count INTEGER NOT NULL,
      tech_thefts_successful INTEGER NOT NULL,
      sabotage_operations INTEGER NOT NULL,
      assassination_attempts INTEGER NOT NULL,
      cyber_attacks_launched INTEGER NOT NULL,
      ebp_points_spent INTEGER NOT NULL,
      cip_points_spent INTEGER NOT NULL,
      counter_intel_successes INTEGER NOT NULL,

      -- Population & Colony Management (from population.toml)
      population_transfers_active INTEGER NOT NULL,
      population_transfers_completed INTEGER NOT NULL,
      population_transfers_lost INTEGER NOT NULL,
      ptu_transferred_total INTEGER NOT NULL,
      colonies_blockaded_count INTEGER NOT NULL,
      blockade_turns_cumulative INTEGER NOT NULL,

      -- Economic Health (from economy.toml)
      treasury_deficit INTEGER NOT NULL, -- Bool as 0 or 1
      infrastructure_damage_total INTEGER NOT NULL,
      salvage_value_recovered INTEGER NOT NULL,
      maintenance_cost_deficit INTEGER NOT NULL,
      tax_penalty_active INTEGER NOT NULL, -- Bool as 0 or 1
      avg_tax_rate_6_turn INTEGER NOT NULL,

      -- Squadron Capacity & Violations (from military.toml)
      fighter_capacity_max INTEGER NOT NULL,
      fighter_capacity_used INTEGER NOT NULL,
      fighter_capacity_violation INTEGER NOT NULL, -- Bool as 0 or 1
      squadron_limit_max INTEGER NOT NULL,
      squadron_limit_used INTEGER NOT NULL,
      squadron_limit_violation INTEGER NOT NULL, -- Bool as 0 or 1
      starbases_actual INTEGER NOT NULL,

      -- House Status (from gameplay.toml)
      autopilot_active INTEGER NOT NULL, -- Bool as 0 or 1
      defensive_collapse_active INTEGER NOT NULL, -- Bool as 0 or 1
      turns_until_elimination INTEGER NOT NULL,
      missed_order_turns INTEGER NOT NULL,

      -- Military
      space_combat_wins INTEGER NOT NULL,
      space_combat_losses INTEGER NOT NULL,
      space_combat_total INTEGER NOT NULL,
      orbital_failures INTEGER NOT NULL,
      orbital_total INTEGER NOT NULL,
      raider_ambush_success INTEGER NOT NULL,
      raider_ambush_attempts INTEGER NOT NULL,
      raider_detected_count INTEGER NOT NULL,
      raider_stealth_success_count INTEGER NOT NULL,
      eli_detection_attempts INTEGER NOT NULL,
      avg_eli_roll REAL NOT NULL, -- float32
      avg_clk_roll REAL NOT NULL, -- float32
      scouts_detected INTEGER NOT NULL,
      scouts_detected_by INTEGER NOT NULL,

      -- Logistics
      capacity_violations_active INTEGER NOT NULL,
      fighters_disbanded INTEGER NOT NULL,
      total_fighters INTEGER NOT NULL,
      idle_carriers INTEGER NOT NULL,
      total_carriers INTEGER NOT NULL,
      total_transports INTEGER NOT NULL,

      -- Ship Counts by Class
      fighter_ships INTEGER NOT NULL,
      corvette_ships INTEGER NOT NULL,
      frigate_ships INTEGER NOT NULL,
      scout_ships INTEGER NOT NULL,
      raider_ships INTEGER NOT NULL,
      destroyer_ships INTEGER NOT NULL,
      cruiser_ships INTEGER NOT NULL,
      light_cruiser_ships INTEGER NOT NULL,
      heavy_cruiser_ships INTEGER NOT NULL,
      battlecruiser_ships INTEGER NOT NULL,
      battleship_ships INTEGER NOT NULL,
      dreadnought_ships INTEGER NOT NULL,
      super_dreadnought_ships INTEGER NOT NULL,
      carrier_ships INTEGER NOT NULL,
      super_carrier_ships INTEGER NOT NULL,
      etac_ships INTEGER NOT NULL,
      troop_transport_ships INTEGER NOT NULL,
      planet_breaker_ships INTEGER NOT NULL,
      total_ships INTEGER NOT NULL,

      -- Ground Unit Counts
      planetary_shield_units INTEGER NOT NULL,
      ground_battery_units INTEGER NOT NULL,
      army_units INTEGER NOT NULL,
      marines_at_colonies INTEGER NOT NULL,
      marines_on_transports INTEGER NOT NULL,
      marine_division_units INTEGER NOT NULL,

      -- Facilities
      total_spaceports INTEGER NOT NULL,
      total_shipyards INTEGER NOT NULL,
      total_drydocks INTEGER NOT NULL,

      -- Intel
      total_invasions INTEGER NOT NULL,
      vulnerable_targets_count INTEGER NOT NULL,
      invasionOrders_generated INTEGER NOT NULL,
      invasionOrders_bombard INTEGER NOT NULL,
      invasionOrders_invade INTEGER NOT NULL,
      invasionOrders_blitz INTEGER NOT NULL,
      invasionOrders_canceled INTEGER NOT NULL,
      colonizeOrdersSubmitted INTEGER NOT NULL,

      -- Phase 2: Multi-turn invasion campaigns
      activeCampaigns_total INTEGER NOT NULL,
      activeCampaigns_scouting INTEGER NOT NULL,
      activeCampaigns_bombardment INTEGER NOT NULL,
      activeCampaigns_invasion INTEGER NOT NULL,
      campaigns_completed_success INTEGER NOT NULL,
      campaigns_abandoned_stalled INTEGER NOT NULL,
      campaigns_abandoned_captured INTEGER NOT NULL,
      campaigns_abandoned_timeout INTEGER NOT NULL,

      -- Invasion attempt tracking
      invasion_attempts_total INTEGER NOT NULL,
      invasion_attempts_successful INTEGER NOT NULL,
      invasion_attempts_failed INTEGER NOT NULL,
      invasion_orders_rejected INTEGER NOT NULL,
      blitz_attempts_total INTEGER NOT NULL,
      blitz_attempts_successful INTEGER NOT NULL,
      blitz_attempts_failed INTEGER NOT NULL,
      bombardment_attempts_total INTEGER NOT NULL,
      bombardment_orders_failed INTEGER NOT NULL,
      invasion_marines_killed INTEGER NOT NULL,
      invasion_defenders_killed INTEGER NOT NULL,

      clk_researched_no_raiders INTEGER NOT NULL, -- Bool as 0 or 1
      scout_count INTEGER NOT NULL,
      spy_planet_missions INTEGER NOT NULL,
      hack_starbase_missions INTEGER NOT NULL,
      total_espionage_missions INTEGER NOT NULL,

      -- Defense
      colonies_without_defense INTEGER NOT NULL,
      total_colonies INTEGER NOT NULL,
      mothballed_fleets_used INTEGER NOT NULL,
      mothballed_fleets_total INTEGER NOT NULL,

      -- Orders
      invalid_orders INTEGER NOT NULL,
      total_orders INTEGER NOT NULL,
      fleet_orders_submitted INTEGER NOT NULL,
      build_orders_submitted INTEGER NOT NULL,
      colonize_orders_submitted INTEGER NOT NULL,

      -- Budget Allocation
      domestikos_budget_allocated INTEGER NOT NULL,
      logothete_budget_allocated INTEGER NOT NULL,
      drungarius_budget_allocated INTEGER NOT NULL,
      eparch_budget_allocated INTEGER NOT NULL,
      build_orders_generated INTEGER NOT NULL,
      pp_spent_construction INTEGER NOT NULL,
      domestikos_requirements_total INTEGER NOT NULL,
      domestikos_requirements_fulfilled INTEGER NOT NULL,
      domestikos_requirements_unfulfilled INTEGER NOT NULL,
      domestikos_requirements_deferred INTEGER NOT NULL,

      -- Build Queue
      total_build_queue_depth INTEGER NOT NULL,
      etac_in_construction INTEGER NOT NULL,
      ships_under_construction INTEGER NOT NULL,
      buildings_under_construction INTEGER NOT NULL,

      -- Commissioning
      ships_commissioned_this_turn INTEGER NOT NULL,
      etac_commissioned_this_turn INTEGER NOT NULL,
      squadrons_commissioned_this_turn INTEGER NOT NULL,

      -- Fleet Activity
      fleets_moved INTEGER NOT NULL,
      systems_colonized INTEGER NOT NULL,
      failed_colonization_attempts INTEGER NOT NULL,
      fleets_with_orders INTEGER NOT NULL,
      stuck_fleets INTEGER NOT NULL,

      -- ETAC Specific
      total_etacs INTEGER NOT NULL,
      etacs_without_orders INTEGER NOT NULL,
      etacs_in_transit INTEGER NOT NULL,

      -- Change Deltas
      colonies_lost INTEGER NOT NULL,
      colonies_gained INTEGER NOT NULL,
      colonies_gained_via_colonization INTEGER NOT NULL,
      colonies_gained_via_conquest INTEGER NOT NULL,
      ships_lost INTEGER NOT NULL,
      ships_gained INTEGER NOT NULL,
      fighters_lost INTEGER NOT NULL,
      fighters_gained INTEGER NOT NULL,

      -- Bilateral Diplomatic Relations
      bilateral_relations TEXT NOT NULL,

      -- Event Counts
      events_order_completed INTEGER NOT NULL,
      events_order_failed INTEGER NOT NULL,
      events_order_rejected INTEGER NOT NULL,
      events_combat_total INTEGER NOT NULL,
      events_bombardment INTEGER NOT NULL,
      events_colony_captured INTEGER NOT NULL,
      events_espionage_total INTEGER NOT NULL,
      events_diplomatic_total INTEGER NOT NULL,
      events_research_total INTEGER NOT NULL,
      events_colony_total INTEGER NOT NULL,

      -- Economic Efficiency & Health
      upkeep_as_percentage_of_income REAL NOT NULL,
      gco_per_population_unit REAL NOT NULL,
      construction_spending_as_percentage_of_income REAL NOT NULL,

      -- Military Effectiveness & Doctrine
      force_projection INTEGER NOT NULL,
      fleet_readiness REAL NOT NULL,
      economic_damage_efficiency REAL NOT NULL,
      capital_ship_ratio REAL NOT NULL,

      -- Diplomatic Strategy
      average_war_duration INTEGER NOT NULL,
      relationship_volatility INTEGER NOT NULL,

      -- Expansion and Empire Stability
      average_colony_development REAL NOT NULL,
      border_friction INTEGER NOT NULL,

      PRIMARY KEY (game_id, turn, house_id)
    );
  """)

proc saveDiagnosticMetrics*(db: DbConn, metrics: DiagnosticMetrics) =
  ## Inserts or updates a DiagnosticMetrics record.
  db.exec(sql"""
    INSERT OR REPLACE INTO diagnostic_metrics (
      game_id, turn, act, rank, house_id, total_systems_on_map,
      treasury_balance, production_per_turn, pu_growth, zero_spend_turns,
      gross_colony_output, net_house_value, tax_rate, total_industrial_units,
      total_population_units, total_population_ptu, population_growth_rate,
      tech_cst, tech_wep, tech_el, tech_sl, tech_ter,
      tech_eli, tech_clk, tech_sld, tech_cic, tech_fd, tech_aco,
      research_erp, research_srp, research_trp, research_breakthroughs,
      research_wasted_erp, research_wasted_srp, turns_at_max_el, turns_at_max_sl,
      maintenance_cost_total, maintenance_shortfall_turns,
      prestige_current, prestige_change, prestige_victory_progress,
      combat_cer_average, bombardment_rounds_total, ground_combat_victories,
      retreats_executed, critical_hits_dealt, critical_hits_received,
      cloaked_ambush_success, shields_activated_count,
      ally_status_count, hostile_status_count, enemy_status_count, neutral_status_count,
      pact_violations_total, dishonored_status_active, diplomatic_isolation_turns,
      pact_formations_total, pact_breaks_total, hostility_declarations_total, war_declarations_total,
      espionage_success_count, espionage_failure_count,
      espionage_detected_count, tech_thefts_successful,
      sabotage_operations, assassination_attempts, cyber_attacks_launched,
      ebp_points_spent, cip_points_spent, counter_intel_successes,
      population_transfers_active, population_transfers_completed,
      population_transfers_lost, ptu_transferred_total,
      colonies_blockaded_count, blockade_turns_cumulative,
      treasury_deficit, infrastructure_damage_total, salvage_value_recovered,
      maintenance_cost_deficit, tax_penalty_active, avg_tax_rate_6_turn,
      fighter_capacity_max, fighter_capacity_used, fighter_capacity_violation,
      squadron_limit_max, squadron_limit_used, squadron_limit_violation,
      starbases_actual,
      autopilot_active, defensive_collapse_active,
      turns_until_elimination, missed_order_turns,
      space_combat_wins, space_combat_losses, space_combat_total,
      orbital_failures, orbital_total,
      raider_ambush_success, raider_ambush_attempts, raider_detected_count,
      raider_stealth_success_count, eli_detection_attempts, avg_eli_roll, avg_clk_roll,
      scouts_detected, scouts_detected_by,
      capacity_violations_active, fighters_disbanded, total_fighters,
      idle_carriers, total_carriers, total_transports,
      fighter_ships, corvette_ships, frigate_ships, scout_ships, raider_ships,
      destroyer_ships, cruiser_ships, light_cruiser_ships, heavy_cruiser_ships,
      battlecruiser_ships, battleship_ships, dreadnought_ships, super_dreadnought_ships,
      carrier_ships, super_carrier_ships, etac_ships, troop_transport_ships, planet_breaker_ships, total_ships,
      planetary_shield_units, ground_battery_units, army_units, marines_at_colonies, marines_on_transports, marine_division_units,
      total_spaceports, total_shipyards, total_drydocks,
      total_invasions, vulnerableTargets_count, invasionOrders_generated,
      invasionOrders_bombard, invasionOrders_invade, invasionOrders_blitz, invasionOrders_canceled,
      colonizeOrdersSubmitted,
      activeCampaigns_total, activeCampaigns_scouting, activeCampaigns_bombardment, activeCampaigns_invasion,
      campaigns_completed_success, campaigns_abandoned_stalled, campaigns_abandoned_captured, campaigns_abandoned_timeout,
      invasion_attempts_total, invasion_attempts_successful, invasion_attempts_failed,
      invasion_orders_rejected, blitz_attempts_total, blitz_attempts_successful,
      blitz_attempts_failed, bombardment_attempts_total, bombardment_orders_failed,
      invasion_marines_killed, invasion_defenders_killed,
      clk_researched_no_raiders, scout_count, spy_planet_missions, hack_starbase_missions, total_espionage_missions,
      colonies_without_defense, total_colonies, mothballed_fleets_used, mothballed_fleets_total,
      invalid_orders, total_orders, fleet_orders_submitted, build_orders_submitted, colonize_orders_submitted,
      domestikos_budget_allocated, logothete_budget_allocated, drungarius_budget_allocated, eparch_budget_allocated,
      build_orders_generated, pp_spent_construction,
      domestikos_requirements_total, domestikos_requirements_fulfilled, domestikos_requirements_unfulfilled, domestikos_requirements_deferred,
      total_build_queue_depth, etac_in_construction, ships_under_construction, buildings_under_construction,
      ships_commissioned_this_turn, etac_commissioned_this_turn, squadrons_commissioned_this_turn,
      fleets_moved, systems_colonized, failed_colonization_attempts, fleets_with_orders, stuck_fleets,
      total_etacs, etacs_without_orders, etacs_in_transit,
      colonies_lost, colonies_gained, colonies_gained_via_colonization, colonies_gained_via_conquest,
      ships_lost, ships_gained, fighters_lost, fighters_gained,
      bilateral_relations,
      events_order_completed, events_order_failed, events_order_rejected,
      events_combat_total, events_bombardment, events_colony_captured,
      events_espionage_total, events_diplomatic_total, events_research_total, events_colony_total,
      upkeep_as_percentage_of_income, gco_per_population_unit, construction_spending_as_percentage_of_income,
      force_projection, fleet_readiness, economic_damage_efficiency, capital_ship_ratio,
      average_war_duration, relationship_volatility,
      average_colony_development, border_friction
    ) VALUES (
      ?, ?, ?, ?, ?, ?, -- gameId, turn, act, rank, houseId, totalSystemsOnMap
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, -- Economy (Core)
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, -- Tech Levels
      ?, ?, ?, ?, -- Research Points
      ?, ?, ?, ?, -- Research Waste Tracking
      ?, ?, ?, ?, ?, -- Maintenance & Prestige
      ?, ?, ?, ?, ?, ?, ?, ?, -- Combat Performance
      ?, ?, ?, ?, ?, ?, ?, -- Diplomatic Status
      ?, ?, ?, ?, -- Treaty Activity Metrics
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, -- Espionage Activity
      ?, ?, ?, ?, ?, ?, -- Population & Colony Management
      ?, ?, ?, ?, ?, ?, -- Economic Health
      ?, ?, ?, ?, ?, ?, ?, -- Squadron Capacity & Violations
      ?, ?, ?, ?, -- House Status
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, -- Military
      ?, ?, ?, ?, ?, ?, -- Logistics
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, -- Ship Counts
      ?, ?, ?, ?, ?, ?, -- Ground Unit Counts
      ?, ?, ?, -- Facilities
      ?, ?, ?, ?, ?, ?, ?, ?, -- Intel
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, -- Invasion attempt tracking
      ?, ?, ?, ?, ?, -- Defense
      ?, ?, ?, ?, ?, -- Orders
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, -- Budget Allocation
      ?, ?, ?, ?, -- Build Queue
      ?, ?, ?, -- Commissioning
      ?, ?, ?, ?, ?, -- Fleet Activity
      ?, ?, ?, -- ETAC Specific
      ?, ?, ?, ?, ?, ?, ?, ?, -- Change Deltas
      ?, -- Bilateral Diplomatic Relations
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, -- Event Counts
      ?, ?, ?, -- Economic Efficiency & Health
      ?, ?, ?, ?, -- Military Effectiveness & Doctrine
      ?, ?, -- Diplomatic Strategy
      ?, ? -- Expansion and Empire Stability
    )
  """,
    metrics.gameId, metrics.turn, metrics.act, metrics.rank, metrics.houseId.uint32, metrics.totalSystemsOnMap,
    metrics.treasuryBalance, metrics.productionPerTurn, metrics.puGrowth, metrics.zeroSpendTurns,
    metrics.grossColonyOutput, metrics.netHouseValue, metrics.taxRate, metrics.totalIndustrialUnits,
    metrics.totalPopulationUnits, metrics.totalPopulationPTU, metrics.populationGrowthRate,
    metrics.techCST, metrics.techWEP, metrics.techEL, metrics.techSL, metrics.techTER,
    metrics.techELI, metrics.techCLK, metrics.techSLD, metrics.techCIC, metrics.techFD, metrics.techACO,
    metrics.researchERP, metrics.researchSRP, metrics.researchTRP, metrics.researchBreakthroughs,
    metrics.researchWastedERP, metrics.researchWastedSRP, metrics.turnsAtMaxEL, metrics.turnsAtMaxSL,
    metrics.maintenanceCostTotal, metrics.maintenanceShortfallTurns,
    metrics.prestigeCurrent, metrics.prestigeChange, metrics.prestigeVictoryProgress,
    metrics.combatCERAverage, metrics.bombardmentRoundsTotal, metrics.groundCombatVictories,
    metrics.retreatsExecuted, metrics.criticalHitsDealt, metrics.criticalHitsReceived,
    metrics.cloakedAmbushSuccess, metrics.shieldsActivatedCount,
    metrics.allyStatusCount, metrics.hostileStatusCount, metrics.enemyStatusCount, metrics.neutralStatusCount,
    metrics.pactViolationsTotal, metrics.dishonoredStatusActive.int, metrics.diplomaticIsolationTurns,
    metrics.pactFormationsTotal, metrics.pactBreaksTotal, metrics.hostilityDeclarationsTotal, metrics.warDeclarationsTotal,
    metrics.espionageSuccessCount, metrics.espionageFailureCount,
    metrics.espionageDetectedCount, metrics.techTheftsSuccessful,
    metrics.sabotageOperations, metrics.assassinationAttempts, metrics.cyberAttacksLaunched,
    metrics.ebpPointsSpent, metrics.cipPointsSpent, metrics.counterIntelSuccesses,
    metrics.populationTransfersActive, metrics.populationTransfersCompleted,
    metrics.populationTransfersLost, metrics.ptuTransferredTotal,
    metrics.coloniesBlockadedCount, metrics.blockadeTurnsCumulative,
    metrics.treasuryDeficit.int, metrics.infrastructureDamageTotal, metrics.salvageValueRecovered,
    metrics.maintenanceCostDeficit, metrics.taxPenaltyActive.int, metrics.avgTaxRate6Turn,
    metrics.fighterCapacityMax, metrics.fighterCapacityUsed, metrics.fighterCapacityViolation.int,
    metrics.squadronLimitMax, metrics.squadronLimitUsed, metrics.squadronLimitViolation.int,
    metrics.starbasesActual,
    metrics.autopilotActive.int, metrics.defensiveCollapseActive.int,
    metrics.turnsUntilElimination, metrics.missedOrderTurns,
    metrics.spaceCombatWins, metrics.spaceCombatLosses, metrics.spaceCombatTotal,
    metrics.orbitalFailures, metrics.orbitalTotal,
    metrics.raiderAmbushSuccess, metrics.raiderAmbushAttempts, metrics.raiderDetectedCount,
    metrics.raiderStealthSuccessCount, metrics.eliDetectionAttempts, metrics.avgEliRoll, metrics.avgClkRoll,
    metrics.scoutsDetected, metrics.scoutsDetectedBy,
    metrics.capacityViolationsActive, metrics.fightersDisbanded, metrics.totalFighters,
    metrics.idleCarriers, metrics.totalCarriers, metrics.totalTransports,
    metrics.fighterShips, metrics.corvetteShips, metrics.frigateShips, metrics.scoutShips, metrics.raiderShips,
    metrics.destroyerShips, metrics.cruiserShips, metrics.lightCruiserShips, metrics.heavyCruiserShips,
    metrics.battlecruiserShips, metrics.battleshipShips, metrics.dreadnoughtShips, metrics.superDreadnoughtShips,
    metrics.carrierShips, metrics.superCarrierShips, metrics.etacShips, metrics.troopTransportShips, metrics.planetBreakerShips, metrics.totalShips,
    metrics.planetaryShieldUnits, metrics.groundBatteryUnits, metrics.armyUnits, metrics.marinesAtColonies, metrics.marinesOnTransports, metrics.marineDivisionUnits,
    metrics.totalSpaceports, metrics.totalShipyards, metrics.totalDrydocks,
    metrics.totalInvasions, metrics.vulnerableTargets_count, metrics.invasionOrders_generated,
    metrics.invasionOrders_bombard, metrics.invasionOrders_invade, metrics.invasionOrders_blitz, metrics.invasionOrders_canceled,
    metrics.colonizeOrdersSubmitted,
    metrics.activeCampaigns_total, metrics.activeCampaigns_scouting, metrics.activeCampaigns_bombardment, metrics.activeCampaigns_invasion,
    metrics.campaigns_completed_success, metrics.campaigns_abandoned_stalled, metrics.campaigns_abandoned_captured, metrics.campaigns_abandoned_timeout,
    metrics.invasionAttemptsTotal, metrics.invasionAttemptsSuccessful, metrics.invasionAttemptsFailed,
    metrics.invasionOrdersRejected, metrics.blitzAttemptsTotal, metrics.blitzAttemptsSuccessful,
    metrics.blitzAttemptsFailed, metrics.bombardmentAttemptsTotal, metrics.bombardmentOrdersFailed,
    metrics.invasionMarinesKilled, metrics.invasionDefendersKilled,
    metrics.clkResearchedNoRaiders.int, metrics.scoutCount, metrics.spyPlanetMissions, metrics.hackStarbaseMissions, metrics.totalEspionageMissions,
    metrics.coloniesWithoutDefense, metrics.totalColonies, metrics.mothballedFleetsUsed, metrics.mothballedFleetsTotal,
    metrics.invalidOrders, metrics.totalOrders, metrics.fleetOrdersSubmitted, metrics.buildOrdersSubmitted, metrics.colonizeOrdersSubmitted,
    metrics.domestikosBudgetAllocated, metrics.logotheteBudgetAllocated, metrics.drungariusBudgetAllocated, metrics.eparchBudgetAllocated,
    metrics.buildOrdersGenerated, metrics.ppSpentConstruction,
    metrics.domestikosRequirementsTotal, metrics.domestikosRequirementsFulfilled, metrics.domestikosRequirementsUnfulfilled, metrics.domestikosRequirementsDeferred,
    metrics.totalBuildQueueDepth, metrics.etacInConstruction, metrics.shipsUnderConstruction, metrics.buildingsUnderConstruction,
    metrics.shipsCommissionedThisTurn, metrics.etacCommissionedThisTurn, metrics.squadronsCommissionedThisTurn,
    metrics.fleetsMoved, metrics.systemsColonized, metrics.failedColonizationAttempts, metrics.fleetsWithOrders, metrics.stuckFleets,
    metrics.totalETACs, metrics.etacsWithoutOrders, metrics.etacsInTransit,
    metrics.coloniesLost, metrics.coloniesGained, metrics.coloniesGainedViaColonization, metrics.coloniesGainedViaConquest,
    metrics.shipsLost, metrics.shipsGained, metrics.fightersLost, metrics.fightersGained,
    metrics.bilateralRelations,
    metrics.eventsOrderCompleted, metrics.eventsOrderFailed, metrics.eventsOrderRejected,
    metrics.eventsCombatTotal, metrics.eventsBombardment, metrics.eventsColonyCaptured,
    metrics.eventsEspionageTotal, metrics.eventsDiplomaticTotal, metrics.eventsResearchTotal, metrics.eventsColonyTotal,
    metrics.upkeepAsPercentageOfIncome, metrics.gcoPerPopulationUnit, metrics.constructionSpendingAsPercentageOfIncome,
    metrics.forceProjection, metrics.fleetReadiness, metrics.economicDamageEfficiency, metrics.capitalShipRatio,
    metrics.averageWarDuration, metrics.relationshipVolatility,
    metrics.averageColonyDevelopment, metrics.borderFriction
  )
