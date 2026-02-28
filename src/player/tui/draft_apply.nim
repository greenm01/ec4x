## Order draft normalization and restore helpers for TUI resume flow.

import std/[algorithm, options, tables]

import ../../engine/types/[command, fleet, zero_turn, tech]
import ../sam/tui_model

proc normalizeDraftPacket*(packet: CommandPacket): CommandPacket =
  ## Stable ordering for deterministic draft fingerprints.
  result = packet
  result.zeroTurnCommands.sort(
    proc(a: ZeroTurnCommand, b: ZeroTurnCommand): int =
      result = cmp(int(a.commandType), int(b.commandType))
      if result != 0:
        return
      result = cmp(
        if a.sourceFleetId.isSome: int(a.sourceFleetId.get()) else: -1,
        if b.sourceFleetId.isSome: int(b.sourceFleetId.get()) else: -1
      )
      if result != 0:
        return
      result = cmp(
        if a.targetFleetId.isSome: int(a.targetFleetId.get()) else: -1,
        if b.targetFleetId.isSome: int(b.targetFleetId.get()) else: -1
      )
  )
  result.fleetCommands.sort(
    proc(a: FleetCommand, b: FleetCommand): int =
      cmp(int(a.fleetId), int(b.fleetId))
  )

proc hasResearchDraft*(allocation: ResearchAllocation): bool =
  if allocation.economic > 0 or allocation.science > 0:
    return true
  for _, pp in allocation.technology:
    if pp > 0:
      return true
  false

proc packetHasDraftData*(packet: CommandPacket): bool =
  packet.zeroTurnCommands.len > 0 or
    packet.fleetCommands.len > 0 or
    packet.buildCommands.len > 0 or
    packet.repairCommands.len > 0 or
    packet.scrapCommands.len > 0 or
    packet.colonyManagement.len > 0 or
    packet.diplomaticCommand.len > 0 or
    packet.populationTransfers.len > 0 or
    packet.terraformCommands.len > 0 or
    packet.espionageActions.len > 0 or
    packet.ebpInvestment > 0 or
    packet.cipInvestment > 0 or
    hasResearchDraft(packet.researchAllocation)

proc applyOrderDraft*(model: var TuiModel, packet: CommandPacket) =
  ## Replace staged UI orders with restored draft content.
  let normalized = normalizeDraftPacket(packet)
  let hasFleetOptimisticData =
    normalized.zeroTurnCommands.len > 0 or
    normalized.fleetCommands.len > 0
  model.ui.stagedFleetCommands.clear()
  model.ui.stagedZeroTurnCommands = @[]
  model.ui.stagedBuildCommands = @[]
  model.ui.stagedRepairCommands = @[]
  model.ui.stagedScrapCommands = @[]
  model.ui.stagedPopulationTransfers = @[]
  model.ui.stagedTerraformCommands = @[]
  model.ui.stagedColonyManagement = @[]
  model.ui.stagedDiplomaticCommands = @[]
  model.ui.stagedEspionageActions = @[]
  model.ui.stagedEbpInvestment = 0
  model.ui.stagedCipInvestment = 0
  model.ui.stagedTaxRate = none(int)
  model.ui.stagedZeroTurnCommands = normalized.zeroTurnCommands
  for cmd in normalized.fleetCommands:
    model.ui.stagedFleetCommands[int(cmd.fleetId)] = cmd
  model.ui.stagedBuildCommands = normalized.buildCommands
  model.ui.stagedRepairCommands = normalized.repairCommands
  model.ui.stagedScrapCommands = normalized.scrapCommands
  model.ui.stagedPopulationTransfers = normalized.populationTransfers
  model.ui.stagedTerraformCommands = normalized.terraformCommands
  model.ui.stagedColonyManagement = normalized.colonyManagement
  model.ui.stagedDiplomaticCommands = normalized.diplomaticCommand
  model.ui.stagedEspionageActions = normalized.espionageActions
  model.ui.stagedEbpInvestment = normalized.ebpInvestment
  model.ui.stagedCipInvestment = normalized.cipInvestment
  model.ui.researchAllocation = normalized.researchAllocation
  for cmd in model.ui.stagedColonyManagement:
    if cmd.taxRate.isSome:
      model.ui.stagedTaxRate = some(int(cmd.taxRate.get()))
      break
  if hasFleetOptimisticData:
    model.reapplyAllOptimisticUpdates()
  model.ui.modifiedSinceSubmit = false
