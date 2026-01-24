## Wire format encoding/decoding for EC4X Nostr payloads
##
## Format:
##   msgpack binary -> zstd compress -> NIP-44 encrypt -> base64 string
##
## All private messages (state, deltas, commands) use msgpack + zstd.
## Join protocol uses unencrypted JSON (see json_join.nim).

import crypto
import compression

proc encodePayload*(
  payload: string,
  senderPrivKey: array[32, byte],
  recipientPubKey: array[32, byte]
): string =
  ## Encode binary payload to NIP-44 encrypted base64 string
  ## Input: msgpack binary data (as string)
  ## Output: base64-encoded encrypted payload
  let compressed = compressPayload(payload)
  encryptNIP44(compressed, senderPrivKey, recipientPubKey)

proc decodePayload*(
  encryptedPayload: string,
  recipientPrivKey: array[32, byte],
  senderPubKey: array[32, byte]
): string =
  ## Decode NIP-44 encrypted payload back to binary
  ## Input: base64-encoded encrypted payload
  ## Output: msgpack binary data (as string)
  let decrypted = decryptNIP44(encryptedPayload, recipientPrivKey, senderPubKey)
  decompressPayload(decrypted)
