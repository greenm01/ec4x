## Unified Per-Game Database Schema
##
## Architecture: One SQLite database per game at: {dataDir}/games/{gameId}/ec4x.db
##
## Tables:
##   Core State: games, houses, systems, lanes, colonies, fleets, ships, orders, diplomacy
##   Intel: intel_systems, intel_fleets, intel_colonies
##   Telemetry: diagnostic_metrics
##   Events: game_events
##
## Design: Events-only (no snapshots, no fleet_tracking)
## Storage: ~5-10MB per 100-turn game

import std/os
import db_connector/db_sqlite

const SchemaVersion* = 2  # Incremented for new unified schema

## ============================================================================
## Core Game State Tables
## ============================================================================

const CreateGamesTable* = """
CREATE TABLE IF NOT EXISTS games (
  id TEXT PRIMARY KEY,              -- UUID v4 (auto-generated)
  name TEXT NOT NULL,               -- Human-readable game name
  description TEXT,                 -- Optional admin notes
  turn INTEGER NOT NULL DEFAULT 0,
  year INTEGER NOT NULL DEFAULT 2001,
  month INTEGER NOT NULL DEFAULT 1,
  phase TEXT NOT NULL,              -- 'Setup', 'Active', 'Paused', 'Completed'
  turn_deadline INTEGER,            -- Unix timestamp (NULL = no deadline)
  transport_mode TEXT NOT NULL,     -- 'localhost' or 'nostr'
  transport_config TEXT,            -- JSON: mode-specific config
  game_setup_json TEXT NOT NULL,    -- GameSetup snapshot (fixed at creation)
  game_config_json TEXT NOT NULL,   -- GameConfig snapshot (fixed at creation)
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK(phase IN ('Setup', 'Active', 'Paused', 'Completed')),
  CHECK(transport_mode IN ('localhost', 'nostr'))
);

CREATE INDEX IF NOT EXISTS idx_games_phase ON games(phase);
CREATE INDEX IF NOT EXISTS idx_games_deadline ON games(turn_deadline)
  WHERE phase = 'Active';
"""

const CreateHousesTable* = """
CREATE TABLE IF NOT EXISTS houses (
  id TEXT PRIMARY KEY,              -- UUID v4
  game_id TEXT NOT NULL,
  name TEXT NOT NULL,               -- "House Alpha", "Empire Beta"
  nostr_pubkey TEXT,                -- npub/hex (NULL for localhost)
  prestige INTEGER NOT NULL DEFAULT 0,
  eliminated BOOLEAN NOT NULL DEFAULT 0,
  home_system_id TEXT,
  color TEXT,                       -- Hex color code for UI
  created_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  UNIQUE(game_id, name)
);

CREATE INDEX IF NOT EXISTS idx_houses_game ON houses(game_id);
CREATE INDEX IF NOT EXISTS idx_houses_pubkey ON houses(nostr_pubkey)
  WHERE nostr_pubkey IS NOT NULL;
"""

const CreateSystemsTable* = """
CREATE TABLE IF NOT EXISTS systems (
  id TEXT PRIMARY KEY,              -- UUID v4
  game_id TEXT NOT NULL,
  name TEXT NOT NULL,               -- "Alpha Centauri", "Sol"
  hex_q INTEGER NOT NULL,           -- Hex coordinate Q
  hex_r INTEGER NOT NULL,           -- Hex coordinate R
  ring INTEGER NOT NULL,            -- Distance from center (0 = center)
  owner_house_id TEXT,              -- NULL if unowned
  created_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (owner_house_id) REFERENCES houses(id) ON DELETE SET NULL,
  UNIQUE(game_id, hex_q, hex_r)
);

CREATE INDEX IF NOT EXISTS idx_systems_game ON systems(game_id);
CREATE INDEX IF NOT EXISTS idx_systems_coords ON systems(game_id, hex_q, hex_r);
CREATE INDEX IF NOT EXISTS idx_systems_owner ON systems(owner_house_id)
  WHERE owner_house_id IS NOT NULL;
"""

const CreateLanesTable* = """
CREATE TABLE IF NOT EXISTS lanes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  from_system_id TEXT NOT NULL,
  to_system_id TEXT NOT NULL,
  lane_type TEXT NOT NULL,          -- 'Major', 'Minor', 'Restricted'
  created_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (from_system_id) REFERENCES systems(id) ON DELETE CASCADE,
  FOREIGN KEY (to_system_id) REFERENCES systems(id) ON DELETE CASCADE,
  UNIQUE(game_id, from_system_id, to_system_id),
  CHECK(lane_type IN ('Major', 'Minor', 'Restricted'))
);

CREATE INDEX IF NOT EXISTS idx_lanes_game ON lanes(game_id);
CREATE INDEX IF NOT EXISTS idx_lanes_from ON lanes(from_system_id);
CREATE INDEX IF NOT EXISTS idx_lanes_to ON lanes(to_system_id);
"""

const CreateColoniesTable* = """
CREATE TABLE IF NOT EXISTS colonies (
  id TEXT PRIMARY KEY,              -- UUID v4
  game_id TEXT NOT NULL,
  system_id TEXT NOT NULL,
  owner_house_id TEXT NOT NULL,
  population INTEGER NOT NULL DEFAULT 0,
  industry INTEGER NOT NULL DEFAULT 0,
  defenses INTEGER NOT NULL DEFAULT 0,
  starbase_level INTEGER NOT NULL DEFAULT 0,
  under_siege BOOLEAN NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (system_id) REFERENCES systems(id) ON DELETE CASCADE,
  FOREIGN KEY (owner_house_id) REFERENCES houses(id) ON DELETE CASCADE,
  UNIQUE(game_id, system_id)        -- One colony per system
);

CREATE INDEX IF NOT EXISTS idx_colonies_game ON colonies(game_id);
CREATE INDEX IF NOT EXISTS idx_colonies_owner ON colonies(owner_house_id);
CREATE INDEX IF NOT EXISTS idx_colonies_system ON colonies(system_id);
"""

const CreateFleetsTable* = """
CREATE TABLE IF NOT EXISTS fleets (
  id TEXT PRIMARY KEY,              -- UUID v4
  game_id TEXT NOT NULL,
  owner_house_id TEXT NOT NULL,
  location_system_id TEXT NOT NULL,
  name TEXT,                        -- Optional fleet name
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (owner_house_id) REFERENCES houses(id) ON DELETE CASCADE,
  FOREIGN KEY (location_system_id) REFERENCES systems(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_fleets_game ON fleets(game_id);
CREATE INDEX IF NOT EXISTS idx_fleets_owner ON fleets(owner_house_id);
CREATE INDEX IF NOT EXISTS idx_fleets_location ON fleets(location_system_id);
"""

const CreateShipsTable* = """
CREATE TABLE IF NOT EXISTS ships (
  id TEXT PRIMARY KEY,              -- UUID v4
  fleet_id TEXT NOT NULL,
  ship_type TEXT NOT NULL,          -- 'Military', 'Spacelift', etc.
  hull_points INTEGER NOT NULL,     -- Current HP
  max_hull_points INTEGER NOT NULL, -- Max HP
  created_at INTEGER NOT NULL,
  FOREIGN KEY (fleet_id) REFERENCES fleets(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ships_fleet ON ships(fleet_id);
"""

const CreateOrdersTable* = """
CREATE TABLE IF NOT EXISTS orders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  house_id TEXT NOT NULL,
  turn INTEGER NOT NULL,
  fleet_id TEXT NOT NULL,
  order_type TEXT NOT NULL,         -- Fleet order type
  target_system_id TEXT,            -- For movement/patrol orders
  target_fleet_id TEXT,             -- For join/rendezvous orders
  params TEXT,                      -- JSON blob for order-specific data
  submitted_at INTEGER NOT NULL,    -- Unix timestamp
  processed BOOLEAN NOT NULL DEFAULT 0,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (house_id) REFERENCES houses(id) ON DELETE CASCADE,
  FOREIGN KEY (fleet_id) REFERENCES fleets(id) ON DELETE CASCADE,
  FOREIGN KEY (target_system_id) REFERENCES systems(id) ON DELETE SET NULL,
  FOREIGN KEY (target_fleet_id) REFERENCES fleets(id) ON DELETE SET NULL,
  UNIQUE(game_id, turn, fleet_id)   -- One order per fleet per turn
);

CREATE INDEX IF NOT EXISTS idx_orders_turn ON orders(game_id, turn);
CREATE INDEX IF NOT EXISTS idx_orders_house_turn ON orders(house_id, turn);
CREATE INDEX IF NOT EXISTS idx_orders_unprocessed ON orders(game_id, turn, processed)
  WHERE processed = 0;
"""

const CreateDiplomacyTable* = """
CREATE TABLE IF NOT EXISTS diplomacy (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  house_a_id TEXT NOT NULL,
  house_b_id TEXT NOT NULL,
  relation TEXT NOT NULL,           -- 'War', 'Peace', 'Alliance', 'NAP'
  turn_established INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (house_a_id) REFERENCES houses(id) ON DELETE CASCADE,
  FOREIGN KEY (house_b_id) REFERENCES houses(id) ON DELETE CASCADE,
  UNIQUE(game_id, house_a_id, house_b_id),
  CHECK(relation IN ('War', 'Peace', 'Alliance', 'NAP')),
  CHECK(house_a_id < house_b_id)    -- Enforce ordering to prevent duplicates
);

CREATE INDEX IF NOT EXISTS idx_diplomacy_game ON diplomacy(game_id);
CREATE INDEX IF NOT EXISTS idx_diplomacy_houses ON diplomacy(house_a_id, house_b_id);
"""

## ============================================================================
## Intel System Tables (Fog of War)
## ============================================================================

const CreateIntelSystemsTable* = """
CREATE TABLE IF NOT EXISTS intel_systems (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  house_id TEXT NOT NULL,           -- Who has this intel
  system_id TEXT NOT NULL,          -- What system
  last_scouted_turn INTEGER NOT NULL,
  visibility_level TEXT NOT NULL,   -- 'owned', 'occupied', 'scouted', 'adjacent'
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (house_id) REFERENCES houses(id) ON DELETE CASCADE,
  FOREIGN KEY (system_id) REFERENCES systems(id) ON DELETE CASCADE,
  UNIQUE(game_id, house_id, system_id),
  CHECK(visibility_level IN ('owned', 'occupied', 'scouted', 'adjacent'))
);

CREATE INDEX IF NOT EXISTS idx_intel_systems_house ON intel_systems(game_id, house_id);
CREATE INDEX IF NOT EXISTS idx_intel_systems_system ON intel_systems(system_id);
"""

const CreateIntelFleetsTable* = """
CREATE TABLE IF NOT EXISTS intel_fleets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  house_id TEXT NOT NULL,           -- Who detected this
  fleet_id TEXT NOT NULL,           -- Enemy fleet
  detected_turn INTEGER NOT NULL,   -- Last seen
  detected_system_id TEXT NOT NULL, -- Where it was seen
  ship_count INTEGER,               -- Approximate count
  ship_types TEXT,                  -- JSON: {"Military": 5, "Spacelift": 2}
  intel_quality TEXT NOT NULL,      -- 'visual', 'scan', 'spy'
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (house_id) REFERENCES houses(id) ON DELETE CASCADE,
  FOREIGN KEY (fleet_id) REFERENCES fleets(id) ON DELETE CASCADE,
  FOREIGN KEY (detected_system_id) REFERENCES systems(id) ON DELETE CASCADE,
  UNIQUE(game_id, house_id, fleet_id),
  CHECK(intel_quality IN ('visual', 'scan', 'spy'))
);

CREATE INDEX IF NOT EXISTS idx_intel_fleets_house ON intel_fleets(game_id, house_id);
CREATE INDEX IF NOT EXISTS idx_intel_fleets_fleet ON intel_fleets(fleet_id);
CREATE INDEX IF NOT EXISTS idx_intel_fleets_staleness ON intel_fleets(game_id, detected_turn);
"""

const CreateIntelColoniesTable* = """
CREATE TABLE IF NOT EXISTS intel_colonies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  house_id TEXT NOT NULL,           -- Who has this intel
  colony_id TEXT NOT NULL,          -- Target colony
  intel_turn INTEGER NOT NULL,      -- When intel was gathered
  population INTEGER,               -- NULL if unknown
  industry INTEGER,
  defenses INTEGER,
  starbase_level INTEGER,
  intel_source TEXT NOT NULL,       -- 'spy', 'capture', 'scan'
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (house_id) REFERENCES houses(id) ON DELETE CASCADE,
  FOREIGN KEY (colony_id) REFERENCES colonies(id) ON DELETE CASCADE,
  UNIQUE(game_id, house_id, colony_id),
  CHECK(intel_source IN ('spy', 'capture', 'scan'))
);

CREATE INDEX IF NOT EXISTS idx_intel_colonies_house ON intel_colonies(game_id, house_id);
CREATE INDEX IF NOT EXISTS idx_intel_colonies_colony ON intel_colonies(colony_id);
CREATE INDEX IF NOT EXISTS idx_intel_colonies_staleness ON intel_colonies(game_id, intel_turn);
"""

## ============================================================================
## Event History Table
## ============================================================================

const CreateGameEventsTable* = """
CREATE TABLE IF NOT EXISTS game_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  turn INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  house_id TEXT,
  fleet_id TEXT,
  system_id TEXT,
  order_type TEXT,
  description TEXT NOT NULL,
  reason TEXT,
  event_data TEXT,                  -- JSON blob for event-specific data
  created_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_events_game ON game_events(game_id);
CREATE INDEX IF NOT EXISTS idx_events_turn ON game_events(game_id, turn);
CREATE INDEX IF NOT EXISTS idx_events_type ON game_events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_fleet ON game_events(fleet_id)
  WHERE fleet_id IS NOT NULL;
"""

## ============================================================================
## Telemetry Table (from telemetry_db.nim - clean, no GOAP)
## ============================================================================

const CreateDiagnosticMetricsTable* = """
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
  light_cruiser_ships INTEGER NOT NULL,
  cruiser_ships INTEGER NOT NULL,
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
  invasion_orders_generated INTEGER NOT NULL,
  invasion_orders_bombard INTEGER NOT NULL,
  invasion_orders_invade INTEGER NOT NULL,
  invasion_orders_blitz INTEGER NOT NULL,
  invasion_orders_canceled INTEGER NOT NULL,
  colonize_orders_submitted INTEGER NOT NULL,

  -- Phase 2: Multi-turn invasion campaigns
  active_campaigns_total INTEGER NOT NULL,
  active_campaigns_scouting INTEGER NOT NULL,
  active_campaigns_bombardment INTEGER NOT NULL,
  active_campaigns_invasion INTEGER NOT NULL,
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
  fleet_commands_submitted INTEGER NOT NULL,
  build_orders_submitted INTEGER NOT NULL,

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

CREATE INDEX IF NOT EXISTS idx_diagnostics_turn ON diagnostic_metrics(game_id, turn);
CREATE INDEX IF NOT EXISTS idx_diagnostics_house ON diagnostic_metrics(game_id, house_id);
"""

## ============================================================================
## Schema Initialization
## ============================================================================

proc createAllTables*(db: DbConn) =
  ## Create all tables for a new game database
  ## Call this once when initializing a new game

  # Core game state
  db.exec(sql CreateGamesTable)
  db.exec(sql CreateHousesTable)
  db.exec(sql CreateSystemsTable)
  db.exec(sql CreateLanesTable)
  db.exec(sql CreateColoniesTable)
  db.exec(sql CreateFleetsTable)
  db.exec(sql CreateShipsTable)
  db.exec(sql CreateOrdersTable)
  db.exec(sql CreateDiplomacyTable)

  # Intel system
  db.exec(sql CreateIntelSystemsTable)
  db.exec(sql CreateIntelFleetsTable)
  db.exec(sql CreateIntelColoniesTable)

  # Event history
  db.exec(sql CreateGameEventsTable)

  # Telemetry
  db.exec(sql CreateDiagnosticMetricsTable)

  # Schema version tracking
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS schema_version (
      version INTEGER PRIMARY KEY,
      applied_at INTEGER NOT NULL
    )
  """)
  db.exec(sql"INSERT OR IGNORE INTO schema_version VALUES (?, unixepoch())", SchemaVersion)

proc defaultDBConfig*(gameId: string, dataDir: string = "data"): tuple[
  dbPath: string,
  gameDir: string
] =
  ## Generate per-game database path
  ## Returns: (dbPath, gameDir)
  let gameDirPath = dataDir / "games" / gameId
  let dbFilePath = gameDirPath / "ec4x.db"
  return (dbFilePath, gameDirPath)
