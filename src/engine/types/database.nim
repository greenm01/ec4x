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
