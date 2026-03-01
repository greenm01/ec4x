## Full GameState serialize/deserialize roundtrip test
import ../src/engine/engine
import ../src/daemon/persistence/msgpack_state
import ../src/common/msgpack_types

echo "Creating game..."
let state = newGame(
  scenarioPath = "scenarios/standard-2-player.kdl",
  dataDir = "/tmp/ec4x_test"
)
echo "Game created: ", state.gameId, " seed=", state.seed

echo "Serializing..."
let packed = serializeGameState(state)
echo "Packed size: ", packed.len, " bytes (base64)"

echo "Deserializing..."
try:
  let restored = deserializeGameState(packed)
  echo "Roundtrip OK: gameId=", restored.gameId, " seed=", restored.seed, " turn=", restored.turn
except:
  echo "Roundtrip FAILED: ", getCurrentExceptionMsg()
