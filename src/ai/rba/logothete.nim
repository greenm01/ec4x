## Logothete Module - Imperial Keeper of Knowledge
##
## Byzantine Logothete (λογοθέτης) - Controller of technological secrets
##
## Public API for research allocation and technology strategy.
##
## Responsibilities:
## - Research budget allocation (ERP/SRP/TRP)
## - Tech cap detection and reallocation
## - Personality-driven research priorities
##
## Usage:
## ```nim
## import ai/rba/logothete
##
## let allocation = logothete.allocateResearch(
##   controller,
##   filtered,
##   researchBudget = 300
## )
## # Returns: ResearchAllocation (economic, science, technology fields)
## ```

import ../../engine/research/types as res_types
import ./logothete/allocation

# Re-export the main public API
export allocation.allocateResearch

# Re-export ResearchAllocation type from engine for convenience
export res_types.ResearchAllocation
