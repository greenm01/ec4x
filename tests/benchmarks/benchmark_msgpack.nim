## Performance Benchmark: msgpack vs JSON for GameState Serialization
##
## This benchmark compares:
## 1. Serialization speed (encode)
## 2. Deserialization speed (decode)
## 3. Size on disk
##
## Run with: nim c -r -d:release tests/benchmarks/benchmark_msgpack.nim

import std/[times, monotimes, json, jsonutils, base64, strformat]
import msgpack4nim
import ../../src/engine/init/game_state
import ../../src/engine/types/game_state
import ../../src/daemon/persistence/msgpack_state

proc benchmark(name: string, iterations: int, fn: proc()) =
  ## Run a benchmark function multiple times and report avg time
  var totalDuration = 0.0

  for i in 0..<iterations:
    let start = getMonoTime()
    fn()
    let finish = getMonoTime()
    totalDuration += inMilliseconds(finish - start).float

  let avgMs = totalDuration / iterations.float
  echo name, ": ", fmt"{avgMs:.3f}", " ms (avg over ", iterations, " iterations)"

proc benchmarkGameStateSerialization() =
  echo "=== GameState Serialization Benchmark ==="
  echo ""

  # Initialize a realistic game state
  let state = initGameState(
    setupPath = "scenarios/standard-4-player.kdl",
    gameName = "Benchmark Test",
    configDir = "config",
    dataDir = "data"
  )

  echo "Game state:"
  echo "  - Houses: ", state.houses.entities.data.len
  echo "  - Systems: ", state.systems.entities.data.len
  echo "  - Colonies: ", state.colonies.entities.data.len
  echo "  - Fleets: ", state.fleets.entities.data.len
  echo "  - Ships: ", state.ships.entities.data.len
  echo ""

  # Benchmark msgpack serialization
  var msgpackData: string
  benchmark("msgpack serialize", 100):
    msgpackData = serializeGameState(state)

  let msgpackSizeBase64 = msgpackData.len
  let msgpackSizeBinary = decode(msgpackData).len

  # Benchmark msgpack deserialization
  var deserializedMsgpack: GameState
  benchmark("msgpack deserialize", 100):
    deserializedMsgpack = deserializeGameState(msgpackData)

  echo ""

  # Benchmark JSON serialization
  var jsonData: string
  benchmark("JSON serialize", 100):
    jsonData = $toJson(state)

  let jsonSize = jsonData.len

  # Benchmark JSON deserialization
  var deserializedJson: GameState
  benchmark("JSON deserialize", 100):
    deserializedJson = parseJson(jsonData).jsonTo(GameState)

  echo ""
  echo "=== Size Comparison ==="
  echo "msgpack (binary):      ", msgpackSizeBinary, " bytes"
  echo "msgpack (base64):      ", msgpackSizeBase64, " bytes"
  echo "JSON:                  ", jsonSize, " bytes"
  echo ""
  let msgpackBinaryPct = 100.0 * msgpackSizeBinary.float / jsonSize.float
  let msgpackBase64Pct = 100.0 * msgpackSizeBase64.float / jsonSize.float
  let spaceSavedPct = 100.0 * (jsonSize - msgpackSizeBinary).float / jsonSize.float

  echo "msgpack binary vs JSON: ", fmt"{msgpackBinaryPct:.1f}", "% of JSON size"
  echo "msgpack base64 vs JSON: ", fmt"{msgpackBase64Pct:.1f}", "% of JSON size"
  echo ""
  echo "Space saved (binary):   ", jsonSize - msgpackSizeBinary, " bytes (", fmt"{spaceSavedPct:.1f}", "%)"

when isMainModule:
  benchmarkGameStateSerialization()
