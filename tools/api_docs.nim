# simple_extract.nim
import std/[json, os, strutils]

proc extractFromFile(file: string): JsonNode =
  result = %*{"procs": [], "types": []}
  let content = readFile(file)
  let module = file.splitFile.name

  for line in content.splitLines:
    let trimmed = line.strip

    # Exported procs
    if trimmed.startsWith("proc ") and '*' in trimmed:
      let sigEnd = if '=' in trimmed: trimmed.find('=') else: trimmed.len
      result["procs"].add(%*{
        "module": module,
        "sig": trimmed[0..<sigEnd].strip
      })

    # Exported types
    elif '*' in trimmed and " = object" in trimmed:
      let name = trimmed.split('*')[0].strip
      result["types"].add(%*{
        "name": name,
        "module": module,
        "kind": "object"
      })
    elif '*' in trimmed and " = enum" in trimmed:
      let name = trimmed.split('*')[0].strip
      result["types"].add(%*{
        "name": name,
        "module": module,
        "kind": "enum"
      })

proc main() =
  var api = %*{"procs": [], "types": []}

  for file in walkDirRec("src", {pcFile}):
    if file.endsWith(".nim"):
      echo "Processing: ", file  # Debug output
      let extracted = extractFromFile(file)
      for p in extracted["procs"]:
        api["procs"].add(p)
      for t in extracted["types"]:
        api["types"].add(t)

  echo api.pretty

main()
