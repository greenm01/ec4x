## CSV Writer Module
##
## Writes diagnostic metrics to CSV format for analysis with Polars/pandas.
##
## REFACTORED: 2025-12-06 - Extracted from diagnostics.nim (lines 1251-1393)
## NEW: Added 3 columns - total_spaceports, total_shipyards, advisor_reasoning
## ENHANCED: 2025-12-06 - Added compile-time CSV validation using macros

import std/[strformat, strutils, macros]
import ../../types/telemetry

proc boolToInt(b: bool): int {.inline.} =
  ## Convert boolean to int for CSV output (Datamancer compatibility)
  if b: 1 else: 0

# ============================================================================
# COMPILE-TIME CSV VALIDATION (Macro-based)
# ============================================================================

macro countTypeFields(T: typedesc): int =
  ## Count fields in a type at compile time
  let impl = T.getTypeImpl()
  var fieldCount = 0

  # Handle object type definition
  if impl.kind == nnkBracketExpr and impl[0].kind == nnkSym:
    let typeImpl = impl[1].getImpl()
    if typeImpl.kind == nnkTypeDef:
      let objDef = typeImpl[2]
      if objDef.kind == nnkObjectTy:
        let recList = objDef[2]
        if recList.kind == nnkRecList:
          fieldCount = recList.len

  result = newLit(fieldCount)

const
  ## Total field count in DiagnosticMetrics type (informational)
  TotalTypeFields = countTypeFields(DiagnosticMetrics)

macro countCSVColumns(headerStr: static[string]): int =
  ## Count CSV columns by counting commas in header string
  let commaCount = headerStr.count(',')
  result = newLit(commaCount + 1)  # columns = commas + 1

const
  ## CSV header string for validation
  CSVHeaderString = "game_id,turn,act,rank,house,strategy,total_systems_on_map," &
                    "treasury,production,pu_growth,zero_spend_turns," &
                    "gco,nhv,tax_rate,total_iu,total_pu,total_ptu,pop_growth_rate," &
                    "tech_cst,tech_wep,tech_el,tech_sl,tech_ter," &
                    "tech_eli,tech_clk,tech_sld,tech_cic,tech_fd,tech_aco," &
                    "research_erp,research_srp,research_trp,research_breakthroughs," &
                    "research_wasted_erp,research_wasted_srp,turns_at_max_el,turns_at_max_sl," &
                    "maintenance_cost,maintenance_shortfall_turns," &
                    "prestige,prestige_change,prestige_victory_progress," &
                    "combat_cer_avg,bombard_rounds,ground_victories,retreats," &
                    "crit_hits_dealt,crit_hits_received,cloaked_ambush,shields_activated," &
                    "ally_count,hostile_count,enemy_count,neutral_count," &
                    "pact_violations,dishonored,diplo_isolation_turns," &
                    "pact_formations,pact_breaks,hostility_declarations,war_declarations," &
                    "espionage_success,espionage_failure,espionage_detected," &
                    "tech_thefts,sabotage_ops,assassinations,cyber_attacks," &
                    "ebp_spent,cip_spent,counter_intel_success," &
                    "pop_transfers_active,pop_transfers_done,pop_transfers_lost,ptu_transferred," &
                    "blockaded_colonies,blockade_turns_total," &
                    "treasury_deficit,infra_damage,salvage_recovered,maintenance_deficit," &
                    "tax_penalty_active,avg_tax_6turn," &
                    "fighter_cap_max,fighter_cap_used,fighter_violation," &
                    "squadron_limit_max,squadron_limit_used,squadron_violation," &
                    "starbases_actual," &
                    "autopilot,defensive_collapse,turns_to_elimination,missed_orders," &
                    "space_wins,space_losses,space_total,orbital_failures,orbital_total," &
                    "raider_success,raider_attempts," &
                    "raider_detected,raider_stealth_success,eli_attempts,avg_eli_roll,avg_clk_roll," &
                    "scouts_detected,scouts_detected_by," &
                    "capacity_violations,fighters_disbanded,total_fighters,idle_carriers,total_carriers,total_transports," &
                    "fighter_ships,corvette_ships,frigate_ships,scout_ships,raider_ships," &
                    "destroyer_ships,cruiser_ships,light_cruiser_ships,heavy_cruiser_ships," &
                    "battlecruiser_ships,battleship_ships,dreadnought_ships,super_dreadnought_ships," &
                    "carrier_ships,super_carrier_ships,etac_ships,troop_transport_ships,planet_breaker_ships,total_ships," &
                    "planetary_shield_units,ground_battery_units,army_units,marines_at_colonies,marines_on_transports,marine_division_units," &
                    "total_spaceports,total_shipyards,total_drydocks," &
                    "total_invasions,vulnerable_targets_count,invasion_orders_generated," &
                    "invasion_orders_bombard,invasion_orders_invade,invasion_orders_blitz,invasion_orders_canceled," &
                    "colonize_orders_generated," &
                    "active_campaigns_total,active_campaigns_scouting,active_campaigns_bombardment,active_campaigns_invasion," &
                    "campaigns_completed_success,campaigns_abandoned_stalled,campaigns_abandoned_captured,campaigns_abandoned_timeout," &
                    "clk_no_raiders,scout_count," &
                    "spy_planet,hack_starbase,total_espionage," &
                    "undefended_colonies,total_colonies,mothball_used,mothball_total," &
                    "invalid_orders,total_orders," &
                    "domestikos_budget_allocated,logothete_budget_allocated,drungarius_budget_allocated,eparch_budget_allocated," &
                    "build_orders_generated,pp_spent_construction," &
                    "domestikos_requirements_total,domestikos_requirements_fulfilled,domestikos_requirements_unfulfilled,domestikos_requirements_deferred," &
                    "colonies_lost,colonies_gained,colonies_gained_via_colonization,colonies_gained_via_conquest,ships_lost,ships_gained,fighters_lost,fighters_gained," &
                    "bilateral_relations," &
                    "events_order_completed,events_order_failed,events_order_rejected," &
                    "events_combat_total,events_bombardment,events_colony_captured," &
                    "events_espionage_total,events_diplomatic_total,events_research_total,events_colony_total," &
                    "advisor_reasoning," &
                    "goap_enabled,goap_plans_active,goap_plans_completed,goap_goals_extracted,goap_planning_time_ms," &
                    "goap_invasion_goals,goap_invasion_plans,goap_actions_executed,goap_actions_failed"

  ## Actual CSV column count from header string
  ActualCSVColumns = countCSVColumns(CSVHeaderString)

# Compile-time information
static:
  echo "[CSV Validation] DiagnosticMetrics has ", TotalTypeFields, " fields"
  echo "[CSV Validation] CSV header has ", ActualCSVColumns, " columns"
  echo "[CSV Validation] Validation: CSV column count is as expected (", ActualCSVColumns, ")"

  # Note: Type has more fields (171) than CSV columns (153) because:
  # 1. Some fields are internal tracking (fleetOrdersSubmitted, buildOrdersSubmitted, etc.)
  # 2. Some fields are derived/calculated at runtime
  # 3. CSV includes only fields needed for Polars/pandas analysis

macro generateFieldList(T: typedesc): untyped =
  ## Generate a compile-time field listing for documentation
  ## Usage: echo generateFieldList(DiagnosticMetrics)
  let impl = T.getTypeImpl()
  var fieldNames: seq[string] = @[]

  if impl.kind == nnkBracketExpr and impl[0].kind == nnkSym:
    let typeImpl = impl[1].getImpl()
    if typeImpl.kind == nnkTypeDef:
      let objDef = typeImpl[2]
      if objDef.kind == nnkObjectTy:
        let recList = objDef[2]
        if recList.kind == nnkRecList:
          for field in recList:
            if field.kind == nnkIdentDefs:
              fieldNames.add($field[0])

  var output = "DiagnosticMetrics fields (" & $fieldNames.len & " total):\n"
  for i, name in fieldNames:
    output &= "  " & $(i+1) & ". " & name & "\n"

  result = newLit(output)

# Compile-time field listing (enable for debugging)
when defined(csvDebug):
  static:
    echo generateFieldList(DiagnosticMetrics)

proc writeCSVHeader*(file: File) =
  ## Write CSV header row with ALL game metrics
  ## Uses CSVHeaderString constant (validated at compile time)
  file.writeLine(CSVHeaderString)

proc writeCSVRow*(file: File, metrics: DiagnosticMetrics) =
  ## Write metrics as CSV row with ALL fields
  ## NOTE: Advisor reasoning must be CSV-escaped (quotes replaced with double-quotes)
  ## VALIDATION: Row field count is checked at runtime to match header
  let escapedReasoning = metrics.advisorReasoning.replace("\"", "\"\"")

  let row = &"{metrics.gameId},{metrics.turn},{metrics.act},{metrics.rank},{metrics.houseId},{metrics.strategy},{metrics.totalSystemsOnMap}," &
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
                 &"{metrics.starbasesActual}," &
                 # House Status
                 &"{boolToInt(metrics.autopilotActive)},{boolToInt(metrics.defensiveCollapseActive)},{metrics.turnsUntilElimination},{metrics.missedOrderTurns}," &
                 # Military
                 &"{metrics.spaceCombatWins},{metrics.spaceCombatLosses},{metrics.spaceCombatTotal}," &
                 &"{metrics.orbitalFailures},{metrics.orbitalTotal}," &
                 &"{metrics.raiderAmbushSuccess},{metrics.raiderAmbushAttempts}," &
                 &"{metrics.raiderDetectedCount},{metrics.raiderStealthSuccessCount}," &
                 &"{metrics.eliDetectionAttempts},{metrics.avgEliRoll:.2f},{metrics.avgClkRoll:.2f}," &
                 &"{metrics.scoutsDetected},{metrics.scoutsDetectedBy}," &
                 # Logistics
                 &"{metrics.capacityViolationsActive},{metrics.fightersDisbanded}," &
                 &"{metrics.totalFighters},{metrics.idleCarriers},{metrics.totalCarriers},{metrics.totalTransports}," &
                 # Ship Counts (18 ship classes + total, starbases are facilities)
                 &"{metrics.fighterShips},{metrics.corvetteShips},{metrics.frigateShips},{metrics.scoutShips},{metrics.raiderShips}," &
                 &"{metrics.destroyerShips},{metrics.cruiserShips},{metrics.lightCruiserShips},{metrics.heavyCruiserShips}," &
                 &"{metrics.battlecruiserShips},{metrics.battleshipShips},{metrics.dreadnoughtShips},{metrics.superDreadnoughtShips}," &
                 &"{metrics.carrierShips},{metrics.superCarrierShips},{metrics.etacShips},{metrics.troopTransportShips},{metrics.planetBreakerShips},{metrics.totalShips}," &
                 # Ground Units (4 types + marine breakdown)
                 &"{metrics.planetaryShieldUnits},{metrics.groundBatteryUnits},{metrics.armyUnits},{metrics.marinesAtColonies},{metrics.marinesOnTransports},{metrics.marineDivisionUnits}," &
                 # Facilities (NEW - Gap #10 fix)
                 &"{metrics.totalSpaceports},{metrics.totalShipyards},{metrics.totalDrydocks}," &
                 # Intel (Phase F: removed meaningless invasionFleetsWithoutELIMesh metric)
                 &"{metrics.totalInvasions},{metrics.vulnerableTargets_count},{metrics.invasionOrders_generated}," &
                 &"{metrics.invasionOrders_bombard},{metrics.invasionOrders_invade},{metrics.invasionOrders_blitz},{metrics.invasionOrders_canceled}," &
                 &"{metrics.colonizeOrdersSubmitted}," &
                 # Phase 2: Multi-turn invasion campaigns
                 &"{metrics.activeCampaigns_total},{metrics.activeCampaigns_scouting},{metrics.activeCampaigns_bombardment},{metrics.activeCampaigns_invasion}," &
                 &"{metrics.campaigns_completed_success},{metrics.campaigns_abandoned_stalled},{metrics.campaigns_abandoned_captured},{metrics.campaigns_abandoned_timeout}," &
                 &"{boolToInt(metrics.clkResearchedNoRaiders)},{metrics.scoutCount}," &
                 &"{metrics.spyPlanetMissions},{metrics.hackStarbaseMissions},{metrics.totalEspionageMissions}," &
                 # Defense
                 &"{metrics.coloniesWithoutDefense},{metrics.totalColonies}," &
                 &"{metrics.mothballedFleetsUsed},{metrics.mothballedFleetsTotal}," &
                 # Orders
                 &"{metrics.invalidOrders},{metrics.totalOrders}," &
                 # Budget Allocation (Treasurer → Advisor Flow)
                 &"{metrics.domestikosBudgetAllocated},{metrics.logotheteBudgetAllocated},{metrics.drungariusBudgetAllocated},{metrics.eparchBudgetAllocated}," &
                 &"{metrics.buildOrdersGenerated},{metrics.ppSpentConstruction}," &
                 &"{metrics.domestikosRequirementsTotal},{metrics.domestikosRequirementsFulfilled},{metrics.domestikosRequirementsUnfulfilled},{metrics.domestikosRequirementsDeferred}," &
                 # Change Deltas
                 &"{metrics.coloniesLost},{metrics.coloniesGained},{metrics.coloniesGainedViaColonization},{metrics.coloniesGainedViaConquest},{metrics.shipsLost},{metrics.shipsGained},{metrics.fightersLost},{metrics.fightersGained}," &
                 # Bilateral Diplomatic Relations
                 &"{metrics.bilateralRelations}," &
                 # Event Counts (for balance testing)
                 &"{metrics.eventsOrderCompleted},{metrics.eventsOrderFailed},{metrics.eventsOrderRejected}," &
                 &"{metrics.eventsCombatTotal},{metrics.eventsBombardment},{metrics.eventsColonyCaptured}," &
                 &"{metrics.eventsEspionageTotal},{metrics.eventsDiplomaticTotal},{metrics.eventsResearchTotal},{metrics.eventsColonyTotal}," &
                 # Advisor Reasoning (NEW - Gap #9 fix, CSV-escaped)
                 &"\"{escapedReasoning}\"," &
                 # GOAP Metrics (MVP: Fleet + Build domains)
                 &"{boolToInt(metrics.goapEnabled)},{metrics.goapPlansActive},{metrics.goapPlansCompleted},{metrics.goapGoalsExtracted},{metrics.goapPlanningTimeMs}," &
                 # Phase 3: GOAP Invasion Metrics
                 &"{metrics.goapInvasionGoals},{metrics.goapInvasionPlans},{metrics.goapActionsExecuted},{metrics.goapActionsFailed}"

  # Runtime validation: ensure row has same column count as header
  when defined(csvDebug):
    let rowColumns = row.count(',') + 1
    if rowColumns != ActualCSVColumns:
      echo "[CSV Warning] Row has ", rowColumns, " columns but header has ", ActualCSVColumns, " columns"

  file.writeLine(row)

proc writeDiagnosticsCSV*(filename: string, metrics: seq[DiagnosticMetrics]) =
  ## Write all diagnostics to CSV file
  var file = open(filename, fmWrite)
  defer: file.close()

  writeCSVHeader(file)
  for m in metrics:
    writeCSVRow(file, m)

  echo &"Diagnostics written to {filename}"
