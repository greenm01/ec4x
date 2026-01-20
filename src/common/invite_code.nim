## Invite code parsing and relay URL handling
##
## Invite codes follow the format: code@host[:port]
##
## Examples:
##   velvet-mountain@play.ec4x.io       -> wss://play.ec4x.io:443
##   velvet-mountain@play.ec4x.io:8080  -> wss://play.ec4x.io:8080
##   velvet-mountain@localhost:8080     -> ws://localhost:8080
##   velvet-mountain                    -> uses default relay from config
##
## TLS rules:
##   - localhost, 127.0.0.1, 192.168.*, 10.* -> ws:// (no TLS)
##   - Everything else -> wss:// (TLS required)

import std/strutils

type
  ParsedInvite* = object
    code*: string      ## The invite code (e.g., "velvet-mountain")
    host*: string      ## Relay host (empty if bare code)
    port*: int         ## Relay port (0 if not specified)
    relayUrl*: string  ## Full relay URL (empty if bare code)

const
  DefaultTlsPort* = 443
  DefaultNoTlsPort* = 80

proc isLocalHost(host: string): bool =
  ## Check if host is a local/private address (no TLS needed)
  host == "localhost" or
  host == "127.0.0.1" or
  host.startsWith("192.168.") or
  host.startsWith("10.") or
  host.startsWith("172.16.") or
  host.startsWith("172.17.") or
  host.startsWith("172.18.") or
  host.startsWith("172.19.") or
  host.startsWith("172.20.") or
  host.startsWith("172.21.") or
  host.startsWith("172.22.") or
  host.startsWith("172.23.") or
  host.startsWith("172.24.") or
  host.startsWith("172.25.") or
  host.startsWith("172.26.") or
  host.startsWith("172.27.") or
  host.startsWith("172.28.") or
  host.startsWith("172.29.") or
  host.startsWith("172.30.") or
  host.startsWith("172.31.")

proc buildRelayUrl*(host: string, port: int): string =
  ## Build a full relay URL from host and port
  ## Automatically selects ws:// or wss:// based on host
  let scheme = if host.isLocalHost(): "ws" else: "wss"
  let effectivePort = if port == 0:
    if host.isLocalHost(): DefaultNoTlsPort else: DefaultTlsPort
  else:
    port
  scheme & "://" & host & ":" & $effectivePort

proc parseInviteCode*(input: string): ParsedInvite =
  ## Parse an invite code string into its components
  ##
  ## Format: code@host[:port]
  ##   code  = word-word (lowercase a-z, hyphen only)
  ##   host  = hostname or IP
  ##   port  = optional, defaults based on TLS
  ##
  ## Returns ParsedInvite with relayUrl empty if no @ present (bare code)
  let trimmed = input.strip().toLowerAscii()
  
  # Find the last @ to split code from relay
  let atIdx = trimmed.rfind('@')
  
  if atIdx == -1:
    # Bare code, no relay specified
    return ParsedInvite(
      code: trimmed,
      host: "",
      port: 0,
      relayUrl: ""
    )
  
  let code = trimmed[0..<atIdx]
  let relayPart = trimmed[atIdx+1..^1]
  
  # Parse host:port from relay part
  var host: string
  var port: int = 0
  
  let colonIdx = relayPart.rfind(':')
  if colonIdx != -1:
    # Check if this is a port or part of IPv6
    let afterColon = relayPart[colonIdx+1..^1]
    if afterColon.len > 0 and afterColon.allCharsInSet({'0'..'9'}):
      # It's a port number
      host = relayPart[0..<colonIdx]
      port = parseInt(afterColon)
    else:
      # No valid port, treat entire thing as host
      host = relayPart
  else:
    host = relayPart
  
  ParsedInvite(
    code: code,
    host: host,
    port: port,
    relayUrl: buildRelayUrl(host, port)
  )

proc normalizeInviteCode*(input: string): string =
  ## Normalize an invite code (strip whitespace, lowercase)
  ## Returns just the code portion, without the relay
  let parsed = parseInviteCode(input)
  parsed.code

proc hasRelay*(invite: ParsedInvite): bool =
  ## Check if the invite includes a relay
  invite.host.len > 0

proc formatInviteCode*(code: string, host: string, port: int = 0): string =
  ## Format an invite code with relay for display/sharing
  ## 
  ## Examples:
  ##   formatInviteCode("velvet-mountain", "play.ec4x.io") 
  ##     -> "velvet-mountain@play.ec4x.io"
  ##   formatInviteCode("velvet-mountain", "play.ec4x.io", 8080)
  ##     -> "velvet-mountain@play.ec4x.io:8080"
  result = code & "@" & host
  if port != 0 and port != DefaultTlsPort and port != DefaultNoTlsPort:
    result.add(":" & $port)

proc isValidInviteCodeFormat*(code: string): bool =
  ## Check if a code follows the word-word format
  ## Codes must be lowercase letters and hyphens only
  if code.len == 0:
    return false
  
  var hasHyphen = false
  for ch in code:
    if ch == '-':
      hasHyphen = true
    elif ch notin {'a'..'z'}:
      return false
  
  # Must have at least one hyphen (word-word format)
  hasHyphen

when isMainModule:
  # Quick tests
  block:
    let p = parseInviteCode("velvet-mountain@play.ec4x.io")
    assert p.code == "velvet-mountain"
    assert p.host == "play.ec4x.io"
    assert p.port == 0
    assert p.relayUrl == "wss://play.ec4x.io:443"
  
  block:
    let p = parseInviteCode("velvet-mountain@play.ec4x.io:8080")
    assert p.code == "velvet-mountain"
    assert p.host == "play.ec4x.io"
    assert p.port == 8080
    assert p.relayUrl == "wss://play.ec4x.io:8080"
  
  block:
    let p = parseInviteCode("velvet-mountain@localhost:8080")
    assert p.code == "velvet-mountain"
    assert p.host == "localhost"
    assert p.port == 8080
    assert p.relayUrl == "ws://localhost:8080"
  
  block:
    let p = parseInviteCode("velvet-mountain@192.168.1.50:8080")
    assert p.code == "velvet-mountain"
    assert p.host == "192.168.1.50"
    assert p.port == 8080
    assert p.relayUrl == "ws://192.168.1.50:8080"
  
  block:
    let p = parseInviteCode("velvet-mountain")
    assert p.code == "velvet-mountain"
    assert p.host == ""
    assert p.relayUrl == ""
    assert not p.hasRelay()
  
  block:
    assert isValidInviteCodeFormat("velvet-mountain")
    assert isValidInviteCodeFormat("a-b")
    assert not isValidInviteCodeFormat("velvetmountain")  # No hyphen
    assert not isValidInviteCodeFormat("Velvet-Mountain")  # Uppercase
    assert not isValidInviteCodeFormat("velvet_mountain")  # Underscore
    assert not isValidInviteCodeFormat("")
  
  echo "All invite code tests passed!"
