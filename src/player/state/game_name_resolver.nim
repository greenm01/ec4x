## Shared game-name resolution helpers for lobby/TUI flows.

import std/[options, strutils, sequtils]

type
  GameNameResolution* = tuple[name: string, source: string]

proc isLikelyUuid*(value: string): bool =
  ## Lightweight UUID shape check for display fallback behavior.
  if value.len != 36:
    return false
  for i in 0..<value.len:
    if i == 8 or i == 13 or i == 18 or i == 23:
      if value[i] != '-':
        return false
    elif value[i] notin {'0'..'9', 'a'..'f', 'A'..'F'}:
      return false
  true

proc resolveGameName*(nameTag: Option[string], gameId: string,
                      cachedName: string = ""): GameNameResolution =
  ## Resolve display name preference: event tag > cached non-UUID > gameId.
  if nameTag.isSome:
    let tagged = nameTag.get().strip()
    if tagged.len > 0:
      return (tagged, "event")

  let cached = cachedName.strip()
  if cached.len > 0 and not isLikelyUuid(cached):
    return (cached, "cache")

  (gameId, "gameId-fallback")

proc gameNameAcronym*(name: string): string =
  ## Build a 3-letter acronym from a game name.
  ## Splits on non-alphanumeric characters and takes first letters.
  var letters: seq[char] = @[]
  var takeNext = true
  for ch in name:
    if ch.isAlphaNumeric():
      if takeNext:
        letters.add(ch)
        takeNext = false
    else:
      takeNext = true
  var resultStr = ""
  for i in 0..<min(3, letters.len):
    resultStr.add(letters[i])
  if resultStr.len < 3:
    var fallbackText = name.filterIt(it.isAlphaNumeric())
    for ch in fallbackText:
      if resultStr.len >= 3:
        break
      if not resultStr.contains(ch):
        resultStr.add(ch)
  resultStr.toUpperAscii()
