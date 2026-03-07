import ../src/daemon/persistence/reader

let dbPath = "data/games/wayside-arrow-pancakes/ec4x.db"
let gameId = "b51fc1ef-6faa-4964-8ee2-01609247d1dc"
let infos = dbGetHousesWithInvites(dbPath, gameId)
for h in infos:
  let status = if h.nostr_pubkey.len > 0: "claimed" else: "pending"
  echo h.name, "|", status, "|", h.invite_code
