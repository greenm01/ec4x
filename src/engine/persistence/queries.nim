## Common queries for diagnostics analysis (DRY)
##
## Reusable SQL query functions for debugging and analysis.
## Designed for colonization bug diagnosis and fleet tracking.

import std/[tables, strformat, logging, strutils]
import db_connector/db_sqlite

proc getColonizationFailures*(db: DbConn, gameId: int64): seq[Row] =
  ## Find turns where colonize orders were issued but no colonies gained
  ## Used for diagnosing colonization bug in Act 2
  ##
  ## Returns rows with columns:
  ## - turn, house_id, colonize_orders_generated,
  ##   colonies_gained_via_colonization, etac_ships
  info &"Querying colonization failures for game {gameId}"
  result = db.getAllRows(
    sql"""
    SELECT
      turn,
      house_id,
      colonize_orders_generated,
      colonies_gained_via_colonization,
      etac_ships
    FROM diagnostics
    WHERE game_id = ?
      AND colonize_orders_generated > 0
      AND colonies_gained_via_colonization = 0
    ORDER BY turn, house_id
  """,
    gameId,
  )
  info &"Found {result.len} colonization failure records"

proc getColonizationWithFleets*(db: DbConn, gameId: int64): seq[Row] =
  ## Find colonization failures with fleet tracking data
  ## Joins diagnostics with game_events to see which fleets had colonize orders
  ##
  ## Returns rows with columns:
  ## - turn, house_id, colonize_orders_generated,
  ##   colonies_gained_via_colonization, etac_ships, fleet_count
  info &"Querying colonization with fleet data for game {gameId}"
  result = db.getAllRows(
    sql"""
    SELECT
      d.turn,
      d.house_id,
      d.colonize_orders_generated,
      d.colonies_gained_via_colonization,
      d.etac_ships,
      COUNT(DISTINCT ft.fleet_id) as fleet_count_with_etacs
    FROM diagnostics d
    LEFT JOIN fleet_tracking ft ON
      ft.game_id = d.game_id AND
      ft.turn = d.turn AND
      ft.house_id = d.house_id AND
      ft.etac_count > 0
    WHERE d.game_id = ?
      AND d.colonize_orders_generated > 0
      AND d.colonies_gained_via_colonization = 0
    GROUP BY d.turn, d.house_id
    ORDER BY d.turn, d.house_id
  """,
    gameId,
  )

proc getFleetLifecycle*(db: DbConn, gameId: int64, fleetId: string): seq[Row] =
  ## Get complete lifecycle for a specific fleet
  ## Used for debugging why ETAC fleets fail to colonize
  ##
  ## Returns rows with columns:
  ## - turn, location_system_id, active_order_type,
  ##   order_target_system_id, has_arrived, etac_count,
  ##   event_type, description, reason
  info &"Querying lifecycle for fleet {fleetId} in game {gameId}"
  result = db.getAllRows(
    sql"""
    SELECT
      ft.turn,
      ft.location_system_id,
      ft.active_order_type,
      ft.order_target_system_id,
      ft.has_arrived,
      ft.etac_count,
      COALESCE(e.event_type, '') as event_type,
      COALESCE(e.description, '') as description,
      COALESCE(e.reason, '') as reason
    FROM fleet_tracking ft
    LEFT JOIN game_events e ON
      e.game_id = ft.game_id AND
      e.turn = ft.turn AND
      e.fleet_id = ft.fleet_id
    WHERE ft.game_id = ? AND ft.fleet_id = ?
    ORDER BY ft.turn
  """,
    gameId,
    fleetId,
  )
  info &"Found {result.len} records for fleet {fleetId}"

proc getFleetsByHouse*(
    db: DbConn, gameId: int64, houseId: string, turn: int
): seq[Row] =
  ## Get all fleets for a specific house at a specific turn
  ## Useful for examining fleet state during colonization failures
  ##
  ## Returns rows with columns:
  ## - fleet_id, location_system_id, active_order_type,
  ##   order_target_system_id, has_arrived, etac_count
  info &"Querying fleets for {houseId} at turn {turn} in game {gameId}"
  result = db.getAllRows(
    sql"""
    SELECT
      fleet_id,
      location_system_id,
      active_order_type,
      order_target_system_id,
      has_arrived,
      etac_count,
      scout_count,
      combat_ships,
      ships_total
    FROM fleet_tracking
    WHERE game_id = ? AND house_id = ? AND turn = ?
    ORDER BY etac_count DESC, fleet_id
  """,
    gameId,
    houseId,
    turn,
  )

proc getOrderExecutionStats*(
    db: DbConn, gameId: int64, orderType: string
): Table[string, int] =
  ## Get success/failure stats for specific order type
  ## Example: getOrderExecutionStats(db, 12345, "Colonize")
  ##
  ## Returns table with event_type → count mappings
  info &"Querying order execution stats for {orderType} in game {gameId}"
  let rows = db.getAllRows(
    sql"""
    SELECT
      event_type,
      COUNT(*) as count
    FROM game_events
    WHERE game_id = ? AND order_type = ?
    GROUP BY event_type
    ORDER BY count DESC
  """,
    gameId,
    orderType,
  )

  result = initTable[string, int]()
  for row in rows:
    result[row[0]] = parseInt(row[1])
  info &"Found {result.len} event types for {orderType} orders"

proc getEventsByType*(db: DbConn, gameId: int64, eventType: string): seq[Row] =
  ## Get all events of a specific type for a game
  ## Useful for examining order failures, arrivals, etc.
  ##
  ## Returns rows with columns:
  ## - turn, house_id, fleet_id, system_id, order_type,
  ##   description, reason
  info &"Querying events of type {eventType} for game {gameId}"
  result = db.getAllRows(
    sql"""
    SELECT
      turn,
      COALESCE(house_id, '') as house_id,
      COALESCE(fleet_id, '') as fleet_id,
      COALESCE(system_id, 0) as system_id,
      COALESCE(order_type, '') as order_type,
      description,
      COALESCE(reason, '') as reason
    FROM game_events
    WHERE game_id = ? AND event_type = ?
    ORDER BY turn, house_id
  """,
    gameId,
    eventType,
  )
  info &"Found {result.len} events of type {eventType}"

proc getETACFleets*(db: DbConn, gameId: int64, turn: int): seq[Row] =
  ## Get all fleets with ETACs at a specific turn
  ## Critical for colonization debugging
  ##
  ## Returns rows with columns:
  ## - house_id, fleet_id, location_system_id,
  ##   active_order_type, order_target_system_id,
  ##   has_arrived, etac_count
  info &"Querying ETAC fleets for turn {turn} in game {gameId}"
  result = db.getAllRows(
    sql"""
    SELECT
      house_id,
      fleet_id,
      location_system_id,
      COALESCE(active_order_type, '') as active_order_type,
      COALESCE(order_target_system_id, 0) as order_target_system_id,
      has_arrived,
      etac_count
    FROM fleet_tracking
    WHERE game_id = ? AND turn = ? AND etac_count > 0
    ORDER BY house_id, etac_count DESC
  """,
    gameId,
    turn,
  )
  info &"Found {result.len} ETAC fleets at turn {turn}"

proc getColonizationSummary*(db: DbConn, gameId: int64): seq[Row] =
  ## Get per-turn summary of colonization activity across all houses
  ## Shows colonization orders vs actual colonizations
  ##
  ## Returns rows with columns:
  ## - turn, total_orders, total_colonized,
  ##   total_etacs, houses_with_orders
  info &"Generating colonization summary for game {gameId}"
  result = db.getAllRows(
    sql"""
    SELECT
      turn,
      SUM(colonize_orders_generated) as total_orders,
      SUM(colonies_gained_via_colonization) as total_colonized,
      AVG(etac_ships) as avg_etacs,
      COUNT(DISTINCT CASE
        WHEN colonize_orders_generated > 0 THEN house_id
      END) as houses_with_orders
    FROM diagnostics
    WHERE game_id = ?
    GROUP BY turn
    ORDER BY turn
  """,
    gameId,
  )
  info &"Generated summary for {result.len} turns"

proc getDiagnosticsByTurn*(db: DbConn, gameId: int64, turn: int): seq[Row] =
  ## Get diagnostic metrics for all houses at a specific turn
  ## Useful for comprehensive turn analysis
  ##
  ## Returns all diagnostic columns for the turn
  info &"Querying diagnostics for turn {turn} in game {gameId}"
  result = db.getAllRows(
    sql"""
    SELECT *
    FROM diagnostics
    WHERE game_id = ? AND turn = ?
    ORDER BY house_id
  """,
    gameId,
    turn,
  )

proc getGameMetadata*(db: DbConn, gameId: int64): Row =
  ## Get game metadata (seed, players, strategies, outcome)
  info &"Querying metadata for game {gameId}"
  result = db.getRow(
    sql"""
    SELECT *
    FROM games
    WHERE game_id = ?
  """,
    gameId,
  )
