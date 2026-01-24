## Shared MessagePack Serialization for Distinct ID Types
##
## This module provides msgpack pack/unpack procs for all distinct ID types
## used across EC4X. Import this module in any file that needs to serialize
## game entities via msgpack.
##
## Usage:
##   import common/msgpack_types
##   # Now pack/unpack work automatically for HouseId, FleetId, etc.

import msgpack4nim
import ../engine/types/core

# =============================================================================
# Custom Serialization for Distinct ID Types
# =============================================================================
#
# msgpack4nim requires explicit pack_type/unpack_type procs for distinct types.
# These procs serialize the underlying uint32 value directly.

proc pack_type*[S](s: S, x: HouseId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var HouseId) =
  var v: uint32
  s.unpack(v)
  x = HouseId(v)

proc pack_type*[S](s: S, x: SystemId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var SystemId) =
  var v: uint32
  s.unpack(v)
  x = SystemId(v)

proc pack_type*[S](s: S, x: ColonyId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var ColonyId) =
  var v: uint32
  s.unpack(v)
  x = ColonyId(v)

proc pack_type*[S](s: S, x: NeoriaId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var NeoriaId) =
  var v: uint32
  s.unpack(v)
  x = NeoriaId(v)

proc pack_type*[S](s: S, x: KastraId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var KastraId) =
  var v: uint32
  s.unpack(v)
  x = KastraId(v)

proc pack_type*[S](s: S, x: FleetId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var FleetId) =
  var v: uint32
  s.unpack(v)
  x = FleetId(v)

proc pack_type*[S](s: S, x: ShipId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var ShipId) =
  var v: uint32
  s.unpack(v)
  x = ShipId(v)

proc pack_type*[S](s: S, x: GroundUnitId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var GroundUnitId) =
  var v: uint32
  s.unpack(v)
  x = GroundUnitId(v)

proc pack_type*[S](s: S, x: ConstructionProjectId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var ConstructionProjectId) =
  var v: uint32
  s.unpack(v)
  x = ConstructionProjectId(v)

proc pack_type*[S](s: S, x: RepairProjectId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var RepairProjectId) =
  var v: uint32
  s.unpack(v)
  x = RepairProjectId(v)

proc pack_type*[S](s: S, x: PopulationTransferId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var PopulationTransferId) =
  var v: uint32
  s.unpack(v)
  x = PopulationTransferId(v)

proc pack_type*[S](s: S, x: ProposalId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var ProposalId) =
  var v: uint32
  s.unpack(v)
  x = ProposalId(v)
