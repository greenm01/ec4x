## Generate a sample SVG for inspection

import ../../src/engine/init/game_state
import ../../src/engine/types/core
import ../../src/player/svg/svg_pkg

let state = initGameState(
  setupPath = "scenarios/standard-4-player.kdl",
  gameName = "Sample SVG",
  configDir = "config",
  dataDir = "data"
)

let svg = generateStarmap(state, HouseId(1))
writeFile("/tmp/ec4x_sample_starmap.svg", svg)
echo "Generated: /tmp/ec4x_sample_starmap.svg"
echo "Size: ", svg.len, " bytes"
