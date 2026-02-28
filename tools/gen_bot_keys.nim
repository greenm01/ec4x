import std/[os, strutils]
import ../src/player/state/identity

let count =
  if paramCount() >= 1: parseInt(paramStr(1))
  else: 2

for _ in 0 ..< count:
  let kp = generateKeyPair()
  echo kp.nsecHex, " ", kp.npubHex
