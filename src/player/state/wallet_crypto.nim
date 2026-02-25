## Cryptographic functions for Wallet Encryption
##
## Uses PBKDF2 (HMAC-SHA256) for Key Derivation and 
## ChaCha20-Poly1305 for Authenticated Encryption.
##
## Wallet container format:
## ```kdl
## encryptedWallet {
##   format "ec4x-wallet"
##   version 1
##   salt "BASE64..."
##   iter 250000
##   nonce "BASE64..."
##   data "BASE64..."
## }
## ```

import std/[base64, sysrand, strutils, options]
import nimcrypto/[pbkdf2, hmac, sha2]
import nim_chacha20_poly1305/[chacha20, chacha20_poly1305, common, poly1305]
import kdl

type
  WalletCipherParams* = object
    salt*: array[16, byte]
    iter*: int
    nonce*: array[12, byte]
    formatVersion*: int

const
  WalletFormatMagic* = "ec4x-wallet"
  WalletFormatVersion* = 1
  DefaultPbkdf2Iter* = 250_000
  EncryptedWalletNode* = "encryptedWallet"

proc deriveKey*(password: string, salt: array[16, byte], iter: int): array[32, byte] =
  ## Derive a 32-byte key from password and salt using PBKDF2-HMAC-SHA256
  var ctx: HMAC[sha256]
  discard ctx.pbkdf2(password, salt, iter, result)

proc encryptWallet*(plaintext: string, password: string, 
                   params: Option[WalletCipherParams] = none(WalletCipherParams)): string =
  ## Encrypt plaintext wallet contents to KDL container string
  var q: WalletCipherParams
  if params.isSome:
    q = params.get()
  else:
    q.iter = DefaultPbkdf2Iter
    q.formatVersion = WalletFormatVersion
    if not urandom(q.salt):
      raise newException(IOError, "Failed to generate random salt")
    if not urandom(q.nonce):
      raise newException(IOError, "Failed to generate random nonce")

  let key = deriveKey(password, q.salt, q.iter)
  
  var ptBytes = newSeq[byte](plaintext.len)
  if plaintext.len > 0:
    copyMem(addr ptBytes[0], unsafeAddr plaintext[0], plaintext.len)
  
  var ctBytes = newSeq[byte](plaintext.len)
  var tag: Tag
  var authData: seq[byte] = @[]
  
  var counter: Counter = 0
  
  chacha20_aead_poly1305_encrypt(
    key,
    q.nonce,
    counter,
    authData,
    ptBytes,
    ctBytes,
    tag
  )
  
  var ctAndTag = newSeq[byte](ctBytes.len + tag.len)
  if ctBytes.len > 0:
    copyMem(addr ctAndTag[0], addr ctBytes[0], ctBytes.len)
  copyMem(addr ctAndTag[ctBytes.len], addr tag[0], tag.len)
  
  # Serialize to KDL
  var content = EncryptedWalletNode & " {\n"
  content.add("  format \"" & WalletFormatMagic & "\"\n")
  content.add("  version " & $q.formatVersion & "\n")
  content.add("  salt \"" & encode(q.salt) & "\"\n")
  content.add("  iter " & $q.iter & "\n")
  content.add("  nonce \"" & encode(q.nonce) & "\"\n")
  content.add("  data \"" & encode(ctAndTag) & "\"\n")
  content.add("}\n")
  
  result = content

proc isEncryptedContainer*(kdlString: string): bool =
  ## Detect if string is an encrypted wallet KDL container
  try:
    let doc = parseKdl(kdlString)
    if doc.len > 0 and doc[0].name == EncryptedWalletNode:
      return true
  except CatchableError:
    discard
  return false

proc decryptWallet*(kdlString: string, password: string): Option[string] =
  ## Decrypt KDL container string to plaintext wallet contents
  try:
    let doc = parseKdl(kdlString)
    if doc.len == 0 or doc[0].name != EncryptedWalletNode:
      return none(string)
      
    let node = doc[0]
    var q: WalletCipherParams
    var dataStr: string
    
    for child in node.children:
      if child.name == "format":
        if child.args[0].kString() != WalletFormatMagic: return none(string)
      elif child.name == "version":
        q.formatVersion = int(child.args[0].kInt())
      elif child.name == "salt":
        let s = decode(child.args[0].kString())
        if s.len != 16: return none(string)
        copyMem(addr q.salt[0], unsafeAddr s[0], 16)
      elif child.name == "iter":
        q.iter = int(child.args[0].kInt())
      elif child.name == "nonce":
        let n = decode(child.args[0].kString())
        if n.len != 12: return none(string)
        copyMem(addr q.nonce[0], unsafeAddr n[0], 12)
      elif child.name == "data":
        dataStr = decode(child.args[0].kString())
        
    if dataStr.len < 16:
      return none(string)
      
    let key = deriveKey(password, q.salt, q.iter)
    let ctLen = dataStr.len - 16
    var ctBytes = newSeq[byte](ctLen)
    var tag: Tag
    if ctLen > 0:
      copyMem(addr ctBytes[0], unsafeAddr dataStr[0], ctLen)
    copyMem(addr tag[0], unsafeAddr dataStr[ctLen], 16)
    
    var ptBytes = newSeq[byte](ctLen)
    var authData: seq[byte] = @[]
    
    var counter: Counter = 0
    let ok = chacha20_aead_poly1305_decrypt_verified(
      key,
      q.nonce,
      counter,
      authData,
      ctBytes,
      ptBytes,
      tag
    )
    
    if not ok:
      return none(string)
      
    if ctLen == 0:
      return some("")
      
    var ptStr = newString(ctLen)
    copyMem(addr ptStr[0], addr ptBytes[0], ctLen)
    return some(ptStr)
    
  except CatchableError:
    return none(string)
