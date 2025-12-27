## Dynamic Prestige Multiplier State
##
## Thread-local storage for current game's prestige multiplier
## This allows prestige calculations throughout the engine to use
## the correct map-size-based scaling without passing it everywhere

import prestige_config
import ../../common/logger


