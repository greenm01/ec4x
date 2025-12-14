## Database persistence types (DoD - data structures only)
##
## This module defines types used for database operations.
## Follows Data-Oriented Design: pure data structures, no behavior.

import ../../ai/analysis/diagnostics/types  # For DiagnosticMetrics

type
  DBConfig* = object
    ## Database configuration (DRY - single source of truth)
    ## Controls how database writes are performed
    dbPath*: string
    enableGameStates*: bool      # Write full GameState snapshots?
    snapshotInterval*: int       # Snapshot every N turns (if enabled)
    pragmas*: seq[string]        # SQLite PRAGMA statements

  WriteResult* = object
    ## Result of database write operation
    ## Used for error handling and diagnostics
    gameId*: int64
    rowsInserted*: int
    success*: bool
    error*: string

proc defaultDBConfig*(dbPath: string): DBConfig =
  ## Create default database configuration
  ## Most games won't need full state snapshots initially
  DBConfig(
    dbPath: dbPath,
    enableGameStates: false,     # Disabled by default (saves space)
    snapshotInterval: 5,         # Every 5 turns if enabled
    pragmas: @[
      "PRAGMA journal_mode=WAL",      # Write-Ahead Logging (faster)
      "PRAGMA synchronous=NORMAL",    # Balance safety/performance
      "PRAGMA cache_size=-64000",     # 64MB cache
      "PRAGMA temp_store=MEMORY"      # Temp tables in memory
    ]
  )
