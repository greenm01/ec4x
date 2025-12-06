## CSV Writer Module
##
## Writes diagnostic metrics to CSV format for analysis with Polars/pandas.
##
## REFACTORED: 2025-12-06 - Extracted from diagnostics.nim (lines 1251-1393)
## NEW: Added 3 columns - total_spaceports, total_shipyards, advisor_reasoning

import std/[strformat, strutils]
import ./types

proc boolToInt(b: bool): int {.inline.} =
  ## Convert boolean to int for CSV output (Datamancer compatibility)
  if b: 1 else: 0

proc writeCSVHeader*(file: File) =
  ## Write CSV header row with ALL game metrics
  file.writeLine("game_id,turn,act,rank,house,strategy," &
                 # Economy (Core)
                 "treasury,production,pu_growth,zero_spend_turns," &
                 "gco,nhv,tax_rate,total_iu,total_pu,total_ptu,pop_growth_rate," &
                 # Tech Levels (11 technologies)
                 "tech_cst,tech_wep,tech_el,tech_sl,tech_ter," &
                 "tech_eli,tech_clk,tech_sld,tech_cic,tech_fd,tech_aco," &
                 # Research & Prestige
                 "research_erp,research_srp,research_trp,research_breakthroughs," &
                 "research_wasted_erp,research_wasted_srp,turns_at_max_el,turns_at_max_sl," &
                 "maintenance_cost,maintenance_shortfall_turns," &
                 "prestige,prestige_change,prestige_victory_progress," &
                 # Combat Performance
                 "combat_cer_avg,bombard_rounds,ground_victories,retreats," &
                 "crit_hits_dealt,crit_hits_received,cloaked_ambush,shields_activated," &
                 # Diplomatic Status (4-level system)
                 "ally_count,hostile_count,enemy_count,neutral_count," &
                 "pact_violations,dishonored,diplo_isolation_turns," &
                 # Treaty Activity Metrics
                 "pact_formations,pact_breaks,hostility_declarations,war_declarations," &
                 # Espionage Activity
                 "espionage_success,espionage_failure,espionage_detected," &
                 "tech_thefts,sabotage_ops,assassinations,cyber_attacks," &
                 "ebp_spent,cip_spent,counter_intel_success," &
                 # Population & Colony Management
                 "pop_transfers_active,pop_transfers_done,pop_transfers_lost,ptu_transferred," &
                 "blockaded_colonies,blockade_turns_total," &
                 # Economic Health
                 "treasury_deficit,infra_damage,salvage_recovered,maintenance_deficit," &
                 "tax_penalty_active,avg_tax_6turn," &
                 # Squadron Capacity & Violations
                 "fighter_cap_max,fighter_cap_used,fighter_violation," &
                 "squadron_limit_max,squadron_limit_used,squadron_violation," &
                 "starbases_required,starbases_actual," &
                 # House Status
                 "autopilot,defensive_collapse,turns_to_elimination,missed_orders," &
                 # Military
                 "space_wins,space_losses,space_total,orbital_failures,orbital_total," &
                 "raider_success,raider_attempts," &
                 # Logistics
                 "capacity_violations,fighters_disbanded,total_fighters,idle_carriers,total_carriers,total_transports," &
                 # Ship Counts (19 ship classes + total)
                 "fighter_ships,corvette_ships,frigate_ships,scout_ships,raider_ships," &
                 "destroyer_ships,cruiser_ships,light_cruiser_ships,heavy_cruiser_ships," &
                 "battlecruiser_ships,battleship_ships,dreadnought_ships,super_dreadnought_ships," &
                 "carrier_ships,super_carrier_ships,starbase_ships,etac_ships,troop_transport_ships,planet_breaker_ships,total_ships," &
                 # Ground Units (4 types)
                 "planetary_shield_units,ground_battery_units,army_units,marine_division_units," &
                 # Facilities (NEW - Gap #10 fix)
                 "total_spaceports,total_shipyards," &
                 # Intel (Phase F: Removed meaningless "invasions_no_eli" metric)
                 "total_invasions,clk_no_raiders,scout_count," &
                 "spy_planet,hack_starbase,total_espionage," &
                 # Defense
                 "undefended_colonies,total_colonies,mothball_used,mothball_total," &
                 # Orders
                 "invalid_orders,total_orders," &
                 # Change Deltas (turn-over-turn)
                 "colonies_lost,colonies_gained,ships_lost,ships_gained,fighters_lost,fighters_gained," &
                 # Bilateral Diplomatic Relations (dynamic, semicolon-separated)
                 "bilateral_relations," &
                 # Advisor Reasoning (NEW - Gap #9 fix)
                 "advisor_reasoning")

proc writeCSVRow*(file: File, metrics: DiagnosticMetrics) =
  ## Write metrics as CSV row with ALL fields
  ## NOTE: Advisor reasoning must be CSV-escaped (quotes replaced with double-quotes)
  let escapedReasoning = metrics.advisorReasoning.replace("\"", "\"\"")

  file.writeLine(&"{metrics.gameId},{metrics.turn},{metrics.act},{metrics.rank},{metrics.houseId},{metrics.strategy}," &
                 # Economy (Core)
                 &"{metrics.treasuryBalance},{metrics.productionPerTurn},{metrics.puGrowth},{metrics.zeroSpendTurns}," &
                 &"{metrics.grossColonyOutput},{metrics.netHouseValue},{metrics.taxRate}," &
                 &"{metrics.totalIndustrialUnits},{metrics.totalPopulationUnits},{metrics.totalPopulationPTU},{metrics.populationGrowthRate}," &
                 # Tech Levels (11 technologies)
                 &"{metrics.techCST},{metrics.techWEP},{metrics.techEL},{metrics.techSL},{metrics.techTER}," &
                 &"{metrics.techELI},{metrics.techCLK},{metrics.techSLD},{metrics.techCIC},{metrics.techFD},{metrics.techACO}," &
                 # Research & Prestige
                 &"{metrics.researchERP},{metrics.researchSRP},{metrics.researchTRP},{metrics.researchBreakthroughs}," &
                 &"{metrics.researchWastedERP},{metrics.researchWastedSRP},{metrics.turnsAtMaxEL},{metrics.turnsAtMaxSL}," &
                 &"{metrics.maintenanceCostTotal},{metrics.maintenanceShortfallTurns}," &
                 &"{metrics.prestigeCurrent},{metrics.prestigeChange},{metrics.prestigeVictoryProgress}," &
                 # Combat Performance
                 &"{metrics.combatCERAverage},{metrics.bombardmentRoundsTotal},{metrics.groundCombatVictories},{metrics.retreatsExecuted}," &
                 &"{metrics.criticalHitsDealt},{metrics.criticalHitsReceived},{metrics.cloakedAmbushSuccess},{metrics.shieldsActivatedCount}," &
                 # Diplomatic Status (4-level system)
                 &"{metrics.allyStatusCount},{metrics.hostileStatusCount},{metrics.enemyStatusCount},{metrics.neutralStatusCount}," &
                 &"{metrics.pactViolationsTotal},{boolToInt(metrics.dishonoredStatusActive)},{metrics.diplomaticIsolationTurns}," &
                 # Treaty Activity Metrics
                 &"{metrics.pactFormationsTotal},{metrics.pactBreaksTotal},{metrics.hostilityDeclarationsTotal},{metrics.warDeclarationsTotal}," &
                 # Espionage Activity
                 &"{metrics.espionageSuccessCount},{metrics.espionageFailureCount},{metrics.espionageDetectedCount}," &
                 &"{metrics.techTheftsSuccessful},{metrics.sabotageOperations},{metrics.assassinationAttempts},{metrics.cyberAttacksLaunched}," &
                 &"{metrics.ebpPointsSpent},{metrics.cipPointsSpent},{metrics.counterIntelSuccesses}," &
                 # Population & Colony Management
                 &"{metrics.populationTransfersActive},{metrics.populationTransfersCompleted},{metrics.populationTransfersLost},{metrics.ptuTransferredTotal}," &
                 &"{metrics.coloniesBlockadedCount},{metrics.blockadeTurnsCumulative}," &
                 # Economic Health
                 &"{boolToInt(metrics.treasuryDeficit)},{metrics.infrastructureDamageTotal},{metrics.salvageValueRecovered},{metrics.maintenanceCostDeficit}," &
                 &"{boolToInt(metrics.taxPenaltyActive)},{metrics.avgTaxRate6Turn}," &
                 # Squadron Capacity & Violations
                 &"{metrics.fighterCapacityMax},{metrics.fighterCapacityUsed},{boolToInt(metrics.fighterCapacityViolation)}," &
                 &"{metrics.squadronLimitMax},{metrics.squadronLimitUsed},{boolToInt(metrics.squadronLimitViolation)}," &
                 &"{metrics.starbasesRequired},{metrics.starbasesActual}," &
                 # House Status
                 &"{boolToInt(metrics.autopilotActive)},{boolToInt(metrics.defensiveCollapseActive)},{metrics.turnsUntilElimination},{metrics.missedOrderTurns}," &
                 # Military
                 &"{metrics.spaceCombatWins},{metrics.spaceCombatLosses},{metrics.spaceCombatTotal}," &
                 &"{metrics.orbitalFailures},{metrics.orbitalTotal}," &
                 &"{metrics.raiderAmbushSuccess},{metrics.raiderAmbushAttempts}," &
                 # Logistics
                 &"{metrics.capacityViolationsActive},{metrics.fightersDisbanded}," &
                 &"{metrics.totalFighters},{metrics.idleCarriers},{metrics.totalCarriers},{metrics.totalTransports}," &
                 # Ship Counts (19 ship classes + total)
                 &"{metrics.fighterShips},{metrics.corvetteShips},{metrics.frigateShips},{metrics.scoutShips},{metrics.raiderShips}," &
                 &"{metrics.destroyerShips},{metrics.cruiserShips},{metrics.lightCruiserShips},{metrics.heavyCruiserShips}," &
                 &"{metrics.battlecruiserShips},{metrics.battleshipShips},{metrics.dreadnoughtShips},{metrics.superDreadnoughtShips}," &
                 &"{metrics.carrierShips},{metrics.superCarrierShips},{metrics.starbaseShips},{metrics.etacShips},{metrics.troopTransportShips},{metrics.planetBreakerShips},{metrics.totalShips}," &
                 # Ground Units (4 types)
                 &"{metrics.planetaryShieldUnits},{metrics.groundBatteryUnits},{metrics.armyUnits},{metrics.marineDivisionUnits}," &
                 # Facilities (NEW - Gap #10 fix)
                 &"{metrics.totalSpaceports},{metrics.totalShipyards}," &
                 # Intel (Phase F: removed meaningless invasionFleetsWithoutELIMesh metric)
                 &"{metrics.totalInvasions}," &
                 &"{boolToInt(metrics.clkResearchedNoRaiders)},{metrics.scoutCount}," &
                 &"{metrics.spyPlanetMissions},{metrics.hackStarbaseMissions},{metrics.totalEspionageMissions}," &
                 # Defense
                 &"{metrics.coloniesWithoutDefense},{metrics.totalColonies}," &
                 &"{metrics.mothballedFleetsUsed},{metrics.mothballedFleetsTotal}," &
                 # Orders
                 &"{metrics.invalidOrders},{metrics.totalOrders}," &
                 # Change Deltas
                 &"{metrics.coloniesLost},{metrics.coloniesGained},{metrics.shipsLost},{metrics.shipsGained},{metrics.fightersLost},{metrics.fightersGained}," &
                 # Bilateral Diplomatic Relations
                 &"{metrics.bilateralRelations}," &
                 # Advisor Reasoning (NEW - Gap #9 fix, CSV-escaped)
                 &"\"{escapedReasoning}\"")

proc writeDiagnosticsCSV*(filename: string, metrics: seq[DiagnosticMetrics]) =
  ## Write all diagnostics to CSV file
  var file = open(filename, fmWrite)
  defer: file.close()

  writeCSVHeader(file)
  for m in metrics:
    writeCSVRow(file, m)

  echo &"Diagnostics written to {filename}"
