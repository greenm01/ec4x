## Eparch Module - Imperial Economic Prefect
##
## Byzantine Eparch (ἔπαρχος) - Prefect controlling markets and infrastructure
##
## Public API for economic development and infrastructure management.
##
## Responsibilities:
## - Generate economic requirements (facilities, terraforming, colonization)
## - Reprioritize requirements based on feedback
##
## Usage:
## ```nim
## import ai/rba/eparch
##
## let economicReqs = eparch.generateEconomicRequirements(c, f, i)
## let reprioritized = eparch.reprioritizeEconomicRequirements(reqs, f, t)
## ```

import ../../common/types/[core, planets]
import ../../engine/[gamestate, orders]
import ./controller_types # For EconomicRequirements
import ./eparch/[terraforming, requirements]

# =============================================================================
# Re-export main public APIs from submodules
# =============================================================================

export requirements.generateEconomicRequirements
export requirements.reprioritizeEconomicRequirements
export terraforming.generateTerraformOrders

# =============================================================================
# Re-export types for convenience
# =============================================================================

export core.SystemId
export planets.PlanetClass
export orders.TerraformOrder
export orders.BuildOrder
export EconomicRequirements, EconomicRequirement, EconomicRequirementType
