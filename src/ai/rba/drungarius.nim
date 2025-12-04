## Drungarius Module - Imperial Spymaster
##
## Byzantine Drungarius (δρουγγάριος) - Commander of intelligence networks
##
## Public API for espionage operations and counter-intelligence.
##
## Responsibilities:
## - Strategic espionage target selection
## - Operation type selection (based on EBP budget)
## - Counter-intelligence decisions (CIP usage)
##
## Usage:
## ```nim
## import ai/rba/drungarius
##
## let attempt = drungarius.generateEspionageAction(
##   controller,
##   filtered,
##   projectedEBP = 300,
##   projectedCIP = 100,
##   rng
## )
## ```

import ../../common/types/core
import ../../engine/gamestate
import ../../engine/espionage/types as esp_types
import ./drungarius/operations

# Re-export the main public API
export operations.selectEspionageTarget
export operations.selectEspionageOperation
export operations.shouldUseCounterIntel
export operations.generateEspionageAction

# Re-export espionage types for convenience
export esp_types.EspionageAction, esp_types.EspionageAttempt
export core.HouseId, core.SystemId
