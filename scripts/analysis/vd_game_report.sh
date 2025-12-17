#!/usr/bin/env bash
# VisiData Interactive Game Analysis
#
# Usage:
#   ./vd_game_report.sh 12345
#
# Opens VisiData with 8 pre-configured analytical views:
#   1. Summary    - Final turn standings (prestige, ships, colonies)
#   2. Ships      - Combat vessels by type (with Act column)
#   3. Facilities - Infrastructure (spaceports, shipyards, starbases)
#   4. Spacelift  - ETACs and troop transports (with Act column)
#   5. Economy    - Turn-by-turn treasury/production (with Act column)
#   6. ETAC       - Colonization fleet tracking (with Act column)
#   7. Tech       - Technology progression (with Act column)
#   8. Idle       - Ships stuck without orders (multi-turn idle)
#
# Act Column:
#   Dynamic game phases calculated by the engine based on map size,
#   colonization progress, and victory conditions (not fixed turn ranges)
#
# VisiData Navigation:
#   Shift+S: Switch between sheets
#   F: Add frequency table for column
#   Shift+F: Frequency histogram
#   +: Aggregate statistics
#   |: Filter rows by pattern
#   g followed by command: Apply to all

set -e

GAME_SEED="${1:-}"
DB_PATH="balance_results/diagnostics/game_${GAME_SEED}.db"

if [ -z "$GAME_SEED" ]; then
  echo "Usage: $0 <game_seed>"
  echo ""
  echo "Example:"
  echo "  $0 12345"
  exit 1
fi

if [ ! -f "$DB_PATH" ]; then
  echo "Error: Database not found: $DB_PATH"
  echo ""
  echo "Run simulation first:"
  echo "  ./bin/run_simulation -s $GAME_SEED"
  exit 1
fi

echo "Opening game seed $GAME_SEED in VisiData..."
echo "Database: $DB_PATH"
echo ""

# Create temporary directory for query results
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Generate CSV files from SQL queries
echo "Preparing analysis views..."

# 1. Summary - Final turn standings
sqlite3 "$DB_PATH" -header -csv <<'SQL' > "$TMP_DIR/1_Summary.csv"
SELECT
    d.house_id,
    MAX(d.turn) as final_turn,
    MAX(d.total_ships) as ships,
    MAX(d.total_colonies) as colonies,
    MAX(d.prestige) as prestige,
    MAX(d.treasury) as treasury,
    SUM(d.ships_gained) as ships_built,
    SUM(d.ships_lost) as ships_lost,
    SUM(d.space_wins) as victories,
    SUM(d.space_losses) as defeats
FROM diagnostics d
WHERE d.turn = (SELECT MAX(turn) FROM diagnostics)
GROUP BY d.house_id
ORDER BY prestige DESC;
SQL

# 2. Ships - Combat vessels over time
sqlite3 "$DB_PATH" -header -csv <<'SQL' > "$TMP_DIR/2_Ships.csv"
SELECT
    act,
    turn,
    house_id,
    total_ships,
    corvette_ships,
    frigate_ships,
    destroyer_ships,
    light_cruiser_ships,
    cruiser_ships,
    heavy_cruiser_ships,
    battlecruiser_ships,
    battleship_ships,
    dreadnought_ships,
    super_dreadnought_ships,
    carrier_ships,
    super_carrier_ships,
    planet_breaker_ships,
    raider_ships,
    fighter_ships,
    scout_ships,
    ships_gained,
    ships_lost,
    space_wins,
    space_losses
FROM diagnostics
ORDER BY turn, house_id;
SQL

# 3. Facilities - Infrastructure over time
sqlite3 "$DB_PATH" -header -csv <<'SQL' > "$TMP_DIR/3_Facilities.csv"
SELECT
    act,
    turn,
    house_id,
    total_spaceports,
    total_shipyards,
    total_drydocks,
    starbases_actual
FROM diagnostics
ORDER BY turn, house_id;
SQL

# 4. Spacelift - Colony ships and transports
sqlite3 "$DB_PATH" -header -csv <<'SQL' > "$TMP_DIR/4_Spacelift.csv"
SELECT
    act,
    turn,
    house_id,
    etac_ships,
    troop_transport_ships,
    total_transports
FROM diagnostics
ORDER BY turn, house_id;
SQL

# 5. Economy - Financial timeline
sqlite3 "$DB_PATH" -header -csv <<'SQL' > "$TMP_DIR/5_Economy.csv"
SELECT
    act,
    turn,
    house_id,
    treasury,
    production,
    maintenance_cost,
    treasury_deficit,
    total_colonies,
    colonies_gained,
    colonies_lost
FROM diagnostics
ORDER BY turn, house_id;
SQL

# 6. ETAC - Colonization activity
sqlite3 "$DB_PATH" -header -csv <<'SQL' > "$TMP_DIR/6_ETAC.csv"
SELECT
    d.act,
    ft.turn,
    ft.house_id,
    ft.fleet_id,
    ft.location_system_id,
    ft.order_target_system_id,
    ft.active_order_type,
    ft.etac_count,
    ft.has_arrived,
    d.total_colonies as house_colonies
FROM fleet_tracking ft
JOIN diagnostics d ON ft.turn = d.turn AND ft.house_id = d.house_id
WHERE ft.etac_count > 0
ORDER BY ft.turn, ft.house_id, ft.fleet_id;
SQL

# 7. Tech - Technology progression
sqlite3 "$DB_PATH" -header -csv <<'SQL' > "$TMP_DIR/7_Tech.csv"
SELECT
    act,
    turn,
    house_id,
    tech_cst,
    tech_wep,
    tech_el,
    tech_sl,
    tech_ter,
    tech_eli,
    tech_clk,
    tech_sld,
    tech_cic,
    tech_fd,
    tech_aco
FROM diagnostics
ORDER BY turn, house_id;
SQL

# 8. Idle - Ships stuck without orders (multi-turn idle)
sqlite3 "$DB_PATH" -header -csv <<'SQL' > "$TMP_DIR/8_Idle.csv"
SELECT
    d.act,
    ft.turn,
    ft.house_id,
    ft.fleet_id,
    ft.location_system_id,
    ft.combat_ships,
    ft.idle_turns_combat,
    ft.scout_count,
    ft.idle_turns_scout,
    ft.etac_count,
    ft.idle_turns_etac,
    ft.troop_transport_count,
    ft.idle_turns_transport,
    ft.active_order_type,
    ft.order_target_system_id
FROM fleet_tracking ft
JOIN diagnostics d ON ft.turn = d.turn AND ft.house_id = d.house_id
WHERE ft.idle_turns_combat > 1
   OR ft.idle_turns_scout > 1
   OR ft.idle_turns_etac > 1
   OR ft.idle_turns_transport > 1
ORDER BY ft.turn, ft.house_id, ft.fleet_id;
SQL

echo "Launching VisiData with 8 analysis sheets..."
echo ""
echo "Sheets:"
echo "  1_Summary    - Final turn standings"
echo "  2_Ships      - Combat vessels (with Act column)"
echo "  3_Facilities - Infrastructure (with Act column)"
echo "  4_Spacelift  - ETACs & transports (with Act column)"
echo "  5_Economy    - Financial timeline (with Act column)"
echo "  6_ETAC       - Colonization activity (with Act column)"
echo "  7_Tech       - Technology progression (with Act column)"
echo "  8_Idle       - Ships stuck without orders (multi-turn idle)"
echo ""
echo "VisiData Tips:"
echo "  Shift+S - Browse/switch between sheets"
echo "  [ / ]   - Sort column ascending/descending"
echo "  F       - Frequency table for column (try on 'act'!)"
echo "  Shift+F - Frequency histogram"
echo "  |       - Filter rows by pattern"
echo "  q       - Quit sheet, qq - quit all"
echo ""

# Launch VisiData with all CSV files
# VisiData will open them as separate sheets
exec vd "$TMP_DIR"/[1-8]_*.csv
