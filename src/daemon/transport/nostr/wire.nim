## Wire format encoding/decoding for EC4X Nostr payloads
##
## Format:
##   KDL string -> zippy compress -> NIP-44 encrypt -> base64 string

import types
import crypto
import compression

proc encodePayload*(
  kdlPayload: string,
  senderPrivKey: array[32, byte],
  recipientPubKey: array[32, byte]
): string =
  ## Encode KDL payload to NIP-44 encrypted base64 string
  let compressed = compressPayload(kdlPayload)
  encryptNIP44(compressed, senderPrivKey, recipientPubKey)

proc decodePayload*(
  encryptedPayload: string,
  recipientPrivKey: array[32, byte],
  senderPubKey: array[32, byte]
): string =
  ## Decode NIP-44 encrypted payload back to KDL string
  let decrypted = decryptNIP44(encryptedPayload, recipientPrivKey, senderPubKey)
  decompressPayload(decrypted)
