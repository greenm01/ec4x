# Player Account Recovery Guide

## How EC4X Identity Works

Each player has a **Nostr keypair**:
- **nsec** (private key) — proves you are you. Never share this.
- **npub** (public key) — your public identity. Games are bound to your npub.

Your wallet is stored at `~/.local/share/ec4x/wallet.kdl`, encrypted with your password using ChaCha20-Poly1305 + PBKDF2-HMAC-SHA256.

There is no central server and no "forgot password" flow. You are your own authority.

## Backing Up Your Keys

1. Open the **Identity Manager** (Ctrl+W from the entry screen)
2. Select the identity you want to back up
3. Press **V** to view keys
4. Press **M** to unmask your nsec
5. Copy both **npub** and **nsec** to a secure location:
   - Password manager (recommended)
   - Encrypted note
   - Paper stored in a safe
6. **Never share your nsec** — anyone with it can impersonate you

## Backing Up Your Password

- Store your wallet password in a password manager
- Without the password, the encrypted `wallet.kdl` file is unrecoverable
- If you have your nsec backed up, you can re-import it into a fresh wallet with a new password

## Recovery Scenarios

### 1. Lost password, have nsec backup

1. Delete `~/.local/share/ec4x/wallet.kdl`
2. Launch the TUI — you'll be prompted to create a new wallet
3. Set a new password
4. Open Identity Manager → press **I** to import your nsec
5. Your npub is restored — rejoin existing games

### 2. Lost/wiped computer, have nsec backup

1. Install EC4X on the new machine
2. Launch the TUI → create a new wallet with a password
3. Import your nsec (Identity Manager → **I**)
4. Connect to relay — your games appear (bound to your npub)

### 3. Lost password AND no nsec backup

- **Permanent lockout** from all games joined with that identity
- You can create a new identity but cannot rejoin existing games
- Other players and the moderator cannot transfer your house to a new npub

### 4. Wallet file corrupted

- If you have your nsec: delete `wallet.kdl`, re-import (same as scenario 1)
- If you don't: same as scenario 3

## Prevention Checklist

- [ ] Created wallet password and stored it in a password manager
- [ ] Backed up nsec for each identity (Identity Manager → V → M → copy)
- [ ] Tested recovery: can you re-derive the same npub from your backed-up nsec?
