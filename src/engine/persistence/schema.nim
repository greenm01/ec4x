## Database schema definitions (DoD - structure definitions)
##
## All table schemas as constants following DRY principle.
## Schema mirrors diagnostic_columns.json for backward compatibility.

import std/logging
import db_connector/db_sqlite
import ../types/database

const SchemaVersion* = 1

const CreateGamesTable* =
  """
CREATE TABLE IF NOT EXISTS games (
  game_id INTEGER PRIMARY KEY,
  timestamp TEXT NOT NULL,
  num_players INTEGER NOT NULL,
  max_turns INTEGER NOT NULL,
  actual_turns INTEGER NOT NULL,
  map_rings INTEGER NOT NULL,
  strategies TEXT NOT NULL,
  victor TEXT,
  victory_type TEXT,
  engine_version TEXT
);
"""

const CreateDiagnosticsTable* =
  """
CREATE TABLE IF NOT EXISTS diagnostics (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL REFERENCES games(game_id),
  turn INTEGER NOT NULL,
  act INTEGER NOT NULL,
  rank INTEGER NOT NULL,
  house_id TEXT NOT NULL,
  strategy TEXT NOT NULL,

  -- Core Metrics (7 columns)
  total_systems_on_map INTEGER NOT NULL,
  treasury REAL NOT NULL,
  production REAL NOT NULL,
  pu_growth REAL NOT NULL,
  zero_spend_turns INTEGER NOT NULL,
  gco REAL NOT NULL,
  nhv REAL NOT NULL,

  -- Economic (11 columns)
  tax_rate REAL NOT NULL,
  total_iu REAL NOT NULL,
  total_pu REAL NOT NULL,
  total_ptu REAL NOT NULL,
  pop_growth_rate REAL NOT NULL,
  maintenance_cost REAL NOT NULL,
  maintenance_shortfall_turns INTEGER NOT NULL,
  treasury_deficit REAL NOT NULL,
  infra_damage REAL NOT NULL,
  salvage_recovered REAL NOT NULL,
  maintenance_deficit REAL NOT NULL,

  -- Tax System (2 columns)
  tax_penalty_active INTEGER NOT NULL,
  avg_tax_6turn REAL NOT NULL,

  -- Technology (11 columns)
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

  -- Research (6 columns)
  research_erp REAL NOT NULL,
  research_srp REAL NOT NULL,
  research_trp REAL NOT NULL,
  research_breakthroughs INTEGER NOT NULL,
  research_wasted_erp REAL NOT NULL,
  research_wasted_srp REAL NOT NULL,
  turns_at_max_el INTEGER NOT NULL,
  turns_at_max_sl INTEGER NOT NULL,

  -- Prestige (3 columns)
  prestige REAL NOT NULL,
  prestige_change REAL NOT NULL,
  prestige_victory_progress REAL NOT NULL,

  -- Combat (8 columns)
  combat_cer_avg REAL NOT NULL,
  bombard_rounds INTEGER NOT NULL,
  ground_victories INTEGER NOT NULL,
  retreats INTEGER NOT NULL,
  crit_hits_dealt INTEGER NOT NULL,
  crit_hits_received INTEGER NOT NULL,
  cloaked_ambush INTEGER NOT NULL,
  shields_activated INTEGER NOT NULL,

  -- Diplomacy (11 columns)
  ally_count INTEGER NOT NULL,
  hostile_count INTEGER NOT NULL,
  enemy_count INTEGER NOT NULL,
  neutral_count INTEGER NOT NULL,
  pact_violations INTEGER NOT NULL,
  dishonored INTEGER NOT NULL,
  diplo_isolation_turns INTEGER NOT NULL,
  pact_formations INTEGER NOT NULL,
  pact_breaks INTEGER NOT NULL,
  hostility_declarations INTEGER NOT NULL,
  war_declarations INTEGER NOT NULL,

  -- Espionage (10 columns)
  espionage_success INTEGER NOT NULL,
  espionage_failure INTEGER NOT NULL,
  espionage_detected INTEGER NOT NULL,
  tech_thefts INTEGER NOT NULL,
  sabotage_ops INTEGER NOT NULL,
  assassinations INTEGER NOT NULL,
  cyber_attacks INTEGER NOT NULL,
  ebp_spent REAL NOT NULL,
  cip_spent REAL NOT NULL,
  counter_intel_success INTEGER NOT NULL,

  -- Population (4 columns)
  pop_transfers_active INTEGER NOT NULL,
  pop_transfers_done INTEGER NOT NULL,
  pop_transfers_lost INTEGER NOT NULL,
  ptu_transferred REAL NOT NULL,

  -- Blockade (2 columns)
  blockaded_colonies INTEGER NOT NULL,
  blockade_turns_total INTEGER NOT NULL,

  -- Fighter Capacity (6 columns)
  fighter_cap_max INTEGER NOT NULL,
  fighter_cap_used INTEGER NOT NULL,
  fighter_violation INTEGER NOT NULL,
  squadron_limit_max INTEGER NOT NULL,
  squadron_limit_used INTEGER NOT NULL,
  squadron_violation INTEGER NOT NULL,

  -- Starbases (1 column)
  starbases_actual INTEGER NOT NULL,

  -- AI State (4 columns)
  autopilot INTEGER NOT NULL,
  defensive_collapse INTEGER NOT NULL,
  turns_to_elimination INTEGER NOT NULL,
  missed_orders INTEGER NOT NULL,

  -- Space Combat (5 columns)
  space_wins INTEGER NOT NULL,
  space_losses INTEGER NOT NULL,
  space_total INTEGER NOT NULL,
  orbital_failures INTEGER NOT NULL,
  orbital_total INTEGER NOT NULL,

  -- Raiders (4 columns)
  raider_success INTEGER NOT NULL,
  raider_attempts INTEGER NOT NULL,
  raider_detected INTEGER NOT NULL,
  raider_stealth_success INTEGER NOT NULL,

  -- Scouts & Stealth (5 columns)
  eli_attempts INTEGER NOT NULL,
  avg_eli_roll REAL NOT NULL,
  avg_clk_roll REAL NOT NULL,
  scouts_detected INTEGER NOT NULL,
  scouts_detected_by INTEGER NOT NULL,

  -- Capacity Violations (2 columns)
  capacity_violations INTEGER NOT NULL,
  fighters_disbanded INTEGER NOT NULL,

  -- Carriers & Transports (4 columns)
  total_fighters INTEGER NOT NULL,
  idle_carriers INTEGER NOT NULL,
  total_carriers INTEGER NOT NULL,
  total_transports INTEGER NOT NULL,

  -- Ship Counts by Type (19 columns)
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

  -- Ground Forces (6 columns)
  planetary_shield_units INTEGER NOT NULL,
  ground_battery_units INTEGER NOT NULL,
  army_units INTEGER NOT NULL,
  marines_at_colonies INTEGER NOT NULL,
  marines_on_transports INTEGER NOT NULL,
  marine_division_units INTEGER NOT NULL,

  -- Infrastructure (3 columns)
  total_spaceports INTEGER NOT NULL,
  total_shipyards INTEGER NOT NULL,
  total_drydocks INTEGER NOT NULL,

  -- Invasion Orders (7 columns)
  total_invasions INTEGER NOT NULL,
  vulnerable_targets_count INTEGER NOT NULL,
  invasion_orders_generated INTEGER NOT NULL,
  invasion_orders_bombard INTEGER NOT NULL,
  invasion_orders_invade INTEGER NOT NULL,
  invasion_orders_blitz INTEGER NOT NULL,
  invasion_orders_canceled INTEGER NOT NULL,

  -- Invasion Attempt Tracking (11 columns - from game events)
  invasion_attempts_total INTEGER NOT NULL DEFAULT 0,
  invasion_attempts_successful INTEGER NOT NULL DEFAULT 0,
  invasion_attempts_failed INTEGER NOT NULL DEFAULT 0,
  invasion_orders_rejected INTEGER NOT NULL DEFAULT 0,
  blitz_attempts_total INTEGER NOT NULL DEFAULT 0,
  blitz_attempts_successful INTEGER NOT NULL DEFAULT 0,
  blitz_attempts_failed INTEGER NOT NULL DEFAULT 0,
  bombardment_attempts_total INTEGER NOT NULL DEFAULT 0,
  bombardment_orders_failed INTEGER NOT NULL DEFAULT 0,
  invasion_marines_killed INTEGER NOT NULL DEFAULT 0,
  invasion_defenders_killed INTEGER NOT NULL DEFAULT 0,

  -- Colonization (1 column)
  colonize_orders_generated INTEGER NOT NULL,

  -- Campaigns (7 columns)
  active_campaigns_total INTEGER NOT NULL,
  active_campaigns_scouting INTEGER NOT NULL,
  active_campaigns_bombardment INTEGER NOT NULL,
  active_campaigns_invasion INTEGER NOT NULL,
  campaigns_completed_success INTEGER NOT NULL,
  campaigns_abandoned_stalled INTEGER NOT NULL,
  campaigns_abandoned_captured INTEGER NOT NULL,
  campaigns_abandoned_timeout INTEGER NOT NULL,

  -- Espionage Orders (4 columns)
  clk_no_raiders INTEGER NOT NULL,
  scout_count INTEGER NOT NULL,
  spy_planet INTEGER NOT NULL,
  hack_starbase INTEGER NOT NULL,
  total_espionage INTEGER NOT NULL,

  -- Colonies (3 columns)
  undefended_colonies INTEGER NOT NULL,
  total_colonies INTEGER NOT NULL,
  mothball_used INTEGER NOT NULL,
  mothball_total INTEGER NOT NULL,

  -- Orders (2 columns)
  invalid_orders INTEGER NOT NULL,
  total_orders INTEGER NOT NULL,

  -- Budget Allocation (5 columns)
  domestikos_budget_allocated REAL NOT NULL,
  logothete_budget_allocated REAL NOT NULL,
  drungarius_budget_allocated REAL NOT NULL,
  eparch_budget_allocated REAL NOT NULL,
  build_orders_generated INTEGER NOT NULL,
  pp_spent_construction REAL NOT NULL,

  -- Requirements (4 columns)
  domestikos_requirements_total INTEGER NOT NULL,
  domestikos_requirements_fulfilled INTEGER NOT NULL,
  domestikos_requirements_unfulfilled INTEGER NOT NULL,
  domestikos_requirements_deferred INTEGER NOT NULL,

  -- Gains/Losses (8 columns)
  colonies_lost INTEGER NOT NULL,
  colonies_gained INTEGER NOT NULL,
  colonies_gained_via_colonization INTEGER NOT NULL,
  colonies_gained_via_conquest INTEGER NOT NULL,
  ships_lost INTEGER NOT NULL,
  ships_gained INTEGER NOT NULL,
  fighters_lost INTEGER NOT NULL,
  fighters_gained INTEGER NOT NULL,

  -- Relations (1 column)
  bilateral_relations INTEGER NOT NULL,

  -- Event Counts (9 columns)
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

  -- AI Reasoning (1 column)
  advisor_reasoning TEXT,

  -- GOAP (9 columns)
  goap_enabled INTEGER NOT NULL,
  goap_plans_active INTEGER NOT NULL,
  goap_plans_completed INTEGER NOT NULL,
  goap_goals_extracted INTEGER NOT NULL,
  goap_planning_time_ms REAL NOT NULL,
  goap_invasion_goals INTEGER NOT NULL,
  goap_invasion_plans INTEGER NOT NULL,
  goap_actions_executed INTEGER NOT NULL,
  goap_actions_failed INTEGER NOT NULL,

  UNIQUE(game_id, turn, house_id)
);
"""

const CreateDiagnosticsIndexes* =
  """
CREATE INDEX IF NOT EXISTS idx_diagnostics_game
  ON diagnostics(game_id);
CREATE INDEX IF NOT EXISTS idx_diagnostics_house
  ON diagnostics(house_id);
CREATE INDEX IF NOT EXISTS idx_diagnostics_turn
  ON diagnostics(game_id, turn);
"""

const CreateGameEventsTable* =
  """
CREATE TABLE IF NOT EXISTS game_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL REFERENCES games(game_id),
  turn INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  house_id TEXT,
  fleet_id TEXT,
  system_id INTEGER,
  order_type TEXT,
  description TEXT NOT NULL,
  reason TEXT,
  event_data TEXT
);
"""

const CreateGameEventsIndexes* =
  """
CREATE INDEX IF NOT EXISTS idx_events_game
  ON game_events(game_id);
CREATE INDEX IF NOT EXISTS idx_events_fleet
  ON game_events(fleet_id);
CREATE INDEX IF NOT EXISTS idx_events_type
  ON game_events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_turn
  ON game_events(game_id, turn);
"""

const CreateFleetTrackingTable* =
  """
CREATE TABLE IF NOT EXISTS fleet_tracking (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id INTEGER NOT NULL REFERENCES games(game_id),
  turn INTEGER NOT NULL,
  fleet_id TEXT NOT NULL,
  house_id TEXT NOT NULL,
  location_system_id INTEGER NOT NULL,
  active_order_type TEXT,
  order_target_system_id INTEGER,
  has_arrived INTEGER NOT NULL,
  ships_total INTEGER NOT NULL,
  etac_count INTEGER NOT NULL,
  scout_count INTEGER NOT NULL,
  combat_ships INTEGER NOT NULL,
  troop_transport_count INTEGER NOT NULL DEFAULT 0,
  idle_turns_combat INTEGER NOT NULL DEFAULT 0,
  idle_turns_scout INTEGER NOT NULL DEFAULT 0,
  idle_turns_etac INTEGER NOT NULL DEFAULT 0,
  idle_turns_transport INTEGER NOT NULL DEFAULT 0,

  UNIQUE(game_id, turn, fleet_id)
);
"""

const CreateFleetTrackingIndexes* =
  """
CREATE INDEX IF NOT EXISTS idx_fleet_tracking_game
  ON fleet_tracking(game_id);
CREATE INDEX IF NOT EXISTS idx_fleet_tracking_fleet
  ON fleet_tracking(fleet_id);
CREATE INDEX IF NOT EXISTS idx_fleet_tracking_turn
  ON fleet_tracking(game_id, turn);
"""

const CreateGameStatesTable* =
  """
CREATE TABLE IF NOT EXISTS game_states (
  game_id INTEGER NOT NULL REFERENCES games(game_id),
  turn INTEGER NOT NULL,
  state_json TEXT NOT NULL,

  PRIMARY KEY (game_id, turn)
);
"""

const CreateGameStatesIndexes* =
  """
CREATE INDEX IF NOT EXISTS idx_states_game
  ON game_states(game_id);
"""

proc defaultDBConfig*(dbPath: string): DBConfig =
  ## Create default database configuration
  ## Most games won't need full state snapshots initially
  DBConfig(
    dbPath: dbPath,
    enableGameStates: false, # Disabled by default (saves space)
    snapshotInterval: 5, # Every 5 turns if enabled
    pragmas:
      @[
        "PRAGMA journal_mode=WAL", # Write-Ahead Logging (faster)
        "PRAGMA synchronous=NORMAL", # Balance safety/performance
        "PRAGMA cache_size=-64000", # 64MB cache
        "PRAGMA temp_store=MEMORY", # Temp tables in memory
      ],
  )

proc initializeDatabase*(db: DbConn): bool =
  ## Initialize database schema (idempotent)
  ## Returns true on success, false on failure
  try:
    # Create tables in dependency order
    info "Creating database schema..."
    db.exec(sql(CreateGamesTable))
    db.exec(sql(CreateDiagnosticsTable))
    db.exec(sql(CreateGameEventsTable))
    db.exec(sql(CreateFleetTrackingTable))
    db.exec(sql(CreateGameStatesTable))

    # Create indexes
    info "Creating database indexes..."
    db.exec(sql(CreateDiagnosticsIndexes))
    db.exec(sql(CreateGameEventsIndexes))
    db.exec(sql(CreateFleetTrackingIndexes))
    db.exec(sql(CreateGameStatesIndexes))

    info "Database schema initialized successfully"
    return true
  except DbError as e:
    error "Failed to initialize database: ", e.msg
    return false
  except Exception as e:
    error "Unexpected error initializing database: ", e.msg
    return false
