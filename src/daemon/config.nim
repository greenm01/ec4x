import std/os
import kdl

type
  DaemonConfig* = object
    data_dir*: string
    poll_interval*: int
    relay_urls*: seq[string]
    replay_retention_turns*: int
    replay_retention_days*: int

proc parseDaemonKdl*(path: string): DaemonConfig =
  let content = readFile(path)
  let doc = parseKdl(content)
  if doc.len == 0:
    raise newException(ValueError, "Empty or invalid KDL config")
  
  let daemonNode = doc[0]
  if daemonNode.name != "daemon":
    raise newException(ValueError, "Root node must be 'daemon'")
    
  for child in daemonNode.children:
    case child.name
    of "data_dir":
      if child.args.len > 0:
        result.data_dir = child.args[0].getString()
    of "poll_interval":
      if child.args.len > 0:
        result.poll_interval = child.args[0].getInt().int
    of "relay_urls":
      for urlNode in child.children:
        if urlNode.name == "url" and urlNode.args.len > 0:
          result.relay_urls.add(urlNode.args[0].getString())
    of "replay_retention_turns":
      if child.args.len > 0:
        result.replay_retention_turns = child.args[0].getInt().int
    of "replay_retention_days":
      if child.args.len > 0:
        result.replay_retention_days = child.args[0].getInt().int
    else:
      discard

  # Defaults
  if result.data_dir.len == 0:
    result.data_dir = "data"
  if result.poll_interval == 0:
    result.poll_interval = 30
  if result.relay_urls.len == 0:
    result.relay_urls = @["ws://localhost:8080"]
  if result.replay_retention_turns == 0:
    result.replay_retention_turns = 2
  if result.replay_retention_days == 0:
    result.replay_retention_days = 7
