import ./types/config

# Global game configuration and setup
# These are true cross-cutting globals loaded once at game start
var gameConfig* {.threadvar.}: GameConfig
var gameSetup* {.threadvar.}: GameSetup
