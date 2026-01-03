## @entities/kastra_ops.nim
##
## Write API for creating and destroying Kastra entities (defensive facilities).
## Ensures consistency between the main `Kastras` collection, the `byColony` index,
## and the ID list within each `Colony` object.
##
## Kastras have tech-modified combat stats applied at construction time (like Ships).

import std/[options, sequtils, tables, math]
import ../state/[engine, id_gen]
import ../types/[game_state, core, facilities, colony]
import ../globals

proc getKastraStats*(kastraClass: KastraClass, weaponsTech: int32 = 1): KastraStats =
  ## Calculate WEP-modified stats for a kastra class
  ## Returns instance-specific stats (AS, DS, WEP level)
  ##
  ## Per docs/specs/04-research_development.md Section 4.3:
  ## "Each WEP tier increases AS and DS by 10% per level"
  ## Formula: stat × (1.10 ^ (WEP_level - 1)), rounded down
  ##
  ## WEP I (level 1) = base stats (no multiplier)
  ## WEP II (level 2) = +10%
  ## WEP III (level 3) = +21% (compound)

  let facilityClass =
    case kastraClass
    of KastraClass.Starbase:
      FacilityClass.Starbase

  let configStats = gameConfig.facilities.facilities[facilityClass]
  let baseAS = configStats.attackStrength
  let baseDS = configStats.defenseStrength

  # Apply WEP multiplier (compound 10% per level above WEP I)
  let modifiedAS =
    if weaponsTech > 1:
      int32(float(baseAS) * pow(1.10, float(weaponsTech - 1)))
    else:
      baseAS

  let modifiedDS =
    if weaponsTech > 1:
      int32(float(baseDS) * pow(1.10, float(weaponsTech - 1)))
    else:
      baseDS

  KastraStats(
    attackStrength: modifiedAS, defenseStrength: modifiedDS, wep: weaponsTech
  )

proc createKastra*(
    state: var GameState, colonyId: ColonyId, kastraClass: KastraClass, wepLevel: int32
): Kastra =
  ## Creates a new kastra (defensive facility), adds it to the entity manager,
  ## and links it to a colony.
  ## Applies WEP tech modifiers to combat stats at construction time.
  let kastraId = state.generateKastraId()

  # Calculate tech-modified stats (permanent at construction)
  let stats = getKastraStats(kastraClass, wepLevel)

  let newKastra = Kastra(
    id: kastraId,
    kastraClass: kastraClass,
    colonyId: colonyId,
    commissionedTurn: state.turn,
    stats: stats,
    isCrippled: false,
  )

  state.addKastra(kastraId, newKastra)
  state.kastras.byColony.mgetOrPut(colonyId, @[]).add(kastraId)

  # Update colony's kastraIds list
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isSome:
    var colony = colonyOpt.get()
    colony.kastraIds.add(kastraId)
    state.updateColony(colonyId, colony)

  return newKastra

proc destroyKastra*(state: var GameState, kastraId: KastraId) =
  ## Destroys a kastra, removing it from all collections.
  ## Uses O(1) lookup via kastra.colonyId (no iteration needed!)
  let kastraOpt = state.kastra(kastraId)
  if kastraOpt.isNone:
    return
  let kastra = kastraOpt.get()

  # Remove from colony's kastraIds list (O(1) colony lookup)
  let colonyOpt = state.colony(kastra.colonyId)
  if colonyOpt.isSome:
    var colony = colonyOpt.get()
    colony.kastraIds.keepIf(
      proc(id: KastraId): bool =
        id != kastraId
    )
    state.updateColony(kastra.colonyId, colony)

  # Remove from byColony index
  if state.kastras.byColony.hasKey(kastra.colonyId):
    state.kastras.byColony[kastra.colonyId] = state.kastras.byColony[
      kastra.colonyId
    ].filterIt(it != kastraId)

  # Remove from main collection
  state.delKastra(kastraId)
