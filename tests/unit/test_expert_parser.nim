import unittest, strutils
import ../../src/player/sam/expert_parser

suite "Expert Mode Parser":

  test "Tokenizer respects quotes":
    let tokens = tokenize(""":f "1st Fleet" move Nova""")
    check tokens == @["f", "1st Fleet", "move", "Nova"]

  test "Fleet command: hold":
    let cmd = parseExpertCommand(""":f "1st Fleet" hold""")
    check cmd.kind == ExpertCommandKind.FleetHold
    check cmd.holdFleetId == "1st Fleet"

  test "Fleet command: move":
    let cmd = parseExpertCommand(":f 1st move Nova")
    check cmd.kind == ExpertCommandKind.FleetMove
    check cmd.fleetId == "1st"
    check cmd.targetSystem == "Nova"

  test "Fleet command: roe":
    let cmd = parseExpertCommand(":f 1st roe 8")
    check cmd.kind == ExpertCommandKind.FleetRoe
    check cmd.roeFleetId == "1st"
    check cmd.roeLevel == 8

  test "Colony command: build":
    let cmd = parseExpertCommand(":c Sol build 5 interceptor")
    check cmd.kind == ExpertCommandKind.ColonyBuild
    check cmd.buildColony == "Sol"
    check cmd.buildQty == 5
    check cmd.buildItem == "interceptor"

  test "Tech command: alloc":
    let cmd = parseExpertCommand(":t wep alloc 50")
    check cmd.kind == ExpertCommandKind.TechAlloc
    check cmd.allocField == "wep"
    check cmd.allocAmount == 50

  test "Spy command: budget":
    let cmd = parseExpertCommand(":s ebp budget 100")
    check cmd.kind == ExpertCommandKind.SpyBudget
    check cmd.budgetType == "ebp"
    check cmd.budgetAmount == 100

  test "Gov command: tax":
    let cmd = parseExpertCommand(":g empire tax 40")
    check cmd.kind == ExpertCommandKind.GovTax
    check cmd.taxRate == 40

  test "Map command: note":
    let cmd = parseExpertCommand(""":m Nova note "Heavily defended"""")
    check cmd.kind == ExpertCommandKind.MapNote
    check cmd.noteSystem == "Nova"
    check cmd.noteText == "Heavily defended"

  test "Parse Error: missing arguments":
    let cmd = parseExpertCommand(":f 1st move")
    check cmd.kind == ExpertCommandKind.ParseError
    check cmd.errorMessage.contains("requires a target system")

  test "Parse Error: unknown category":
    let cmd = parseExpertCommand(":x 1st move")
    check cmd.kind == ExpertCommandKind.ParseError
    check cmd.errorMessage.contains("Unknown category")
