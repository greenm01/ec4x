## Eparch Module - Imperial Economic Prefect
##
## Byzantine Eparch (ἔπαρχος) - Prefect controlling markets and infrastructure
##
## Public API for economic development and infrastructure management.
##
## Responsibilities:
## - Colonization strategy (ETAC dispatch, target selection)
## - Terraforming strategy (planetary development)
## - Facility construction (shipyards, spaceports)
## - Economic policy (future: taxation, trade)
##
## Usage:
## ```nim
## import ai/rba/eparch
##
## # Generate requirements
## eparch.generateColonizationOrders(controller, filtered, intel, act)
##
## # Execute orders from requirements
## let facilityOrders = eparch.generateFacilityBuildOrders(...)
## let terraformOrders = eparch.generateTerraformOrders(...)
## ```

import ../../common/types/[core, planets]
import ../../engine/[gamestate, orders]
import ./eparch/[terraforming, colonization, facility_construction]

# =============================================================================
# Re-export main public APIs from submodules
# =============================================================================

export terraforming.generateTerraformOrders
export colonization.generateColonizationOrders
export facility_construction.generateFacilityBuildOrders

# =============================================================================
# Re-export types for convenience
# =============================================================================

export core.SystemId
export planets.PlanetClass
export orders.TerraformOrder
export orders.BuildOrder
