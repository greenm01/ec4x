## Unit tests for sectioned TUI rules snapshot sync.

import std/[unittest, options, tables]

import ../../src/common/config_sync
import ../../src/engine/config/engine as config_engine
import ../../src/engine/globals
import ../../src/engine/types/config

gameConfig = config_engine.loadGameConfig()

suite "Config Sync Snapshot":
  test "build snapshot has required sections and capabilities":
    let snapshot = buildTuiRulesSnapshot(gameConfig)
    check snapshot.schemaVersion == ConfigSchemaVersion
    check snapshot.sections.tech.isSome
    check snapshot.sections.ships.isSome
    check snapshot.sections.groundUnits.isSome
    check snapshot.sections.facilities.isSome
    check snapshot.sections.construction.isSome
    check snapshot.sections.limits.isSome
    check snapshot.sections.economy.isSome
    check snapshot.hasRequiredSections()
    check snapshot.hasRequiredCapabilities()

  test "hash is stable for same snapshot content":
    let snapshotA = buildTuiRulesSnapshot(gameConfig)
    let snapshotB = buildTuiRulesSnapshot(gameConfig)
    check snapshotA.configHash == snapshotB.configHash

  test "toGameConfig materializes minimal config":
    let snapshot = buildTuiRulesSnapshot(gameConfig)
    let configOpt = toGameConfig(snapshot)
    check configOpt.isSome
    let cfg = configOpt.get()
    check cfg.tech.el.levels.len > 0
    check cfg.ships.ships.len > 0
    check cfg.groundUnits.units.len > 0
    check cfg.facilities.facilities.len > 0

  test "toGameConfig rejects semantically empty content":
    let emptySnapshot = buildTuiRulesSnapshot(GameConfig())
    check emptySnapshot.hasRequiredSections()
    check emptySnapshot.hasRequiredCapabilities()
    check not emptySnapshot.hasRequiredContent()
    check emptySnapshot.requiredContentError().len > 0
    let configOpt = toGameConfig(emptySnapshot)
    check configOpt.isNone
