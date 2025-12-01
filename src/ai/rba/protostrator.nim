## Protostrator Module - Imperial Master of Protocol
##
## Byzantine Protostrator (πρωτοστράτωρ) - Master of ceremonies managing foreign relations
##
## Public API for diplomatic assessment and relationship management.
##
## Responsibilities:
## - Diplomatic relationship assessment
## - Alliance/pact recommendations
## - War/peace evaluations
## - Foreign policy strategy
##
## Usage:
## ```nim
## import ai/rba/protostrator
##
## let assessment = protostrator.assessDiplomaticSituation(
##   controller,
##   filtered
## )
## ```

import std/[tables, options, sequtils]
import ../../common/types/[core, diplomacy]
import ../../engine/[gamestate, fog_of_war]
import ./controller_types
import ./protostrator/assessment

# Re-export the main public API
export assessment.assessDiplomaticSituation
export assessment.getOwnedFleets
export assessment.getFleetStrength

# Re-export types for convenience
export core.HouseId
export diplomacy.DiplomaticState
