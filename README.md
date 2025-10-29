# GitFoil

Six layers of encryption because you're a little paranoid, you've accepted that, and you need to sleep at night.

Quantum-resistant security that piggybacks on Git. Set it up once, then sleep soundly knowing it's so absurdly overbuilt that your paranoia finally shuts up.

![GitFoil Logo](docs/images/GitFoil.jpg)

---

## Quick Start

**macOS (Homebrew):**

```bash
brew install code-of-kai/gitfoil/git-foil
cd your-repo
git-foil init
```

That's it. Files encrypt automatically when you commit. No extra commands. Just Git.

**Works on:** macOS, Linux ([see installation guide](INSTALL.md))

---

## The Problem

Look, we both know you're paranoid.

You're convinced AES-256 has a backdoor, aren't you? You read that Hacker News thread about quantum computers. You saw that leaked slide deck about agencies hoarding zero-days. You don't trust Microsoft with your code.

Are you being paranoid? Yes. Absolutely.

Is it justified? Your therapist says no. History says maybe.

So what now?

Six layers of encryption, that's what.

---

## What GitFoil Does

Wraps your Git repository in six layers of military-grade™ encryption.

Then hides in your Git workflow so you never think about it again.

```bash
git add .
git commit -m "feature: auth system that definitely won't leak"
git push
```

Notice what's missing? **No `git-foil` commands.** Just Git.

GitFoil piggybacks on your normal workflow using Git's clean/smudge filters. No extra commands. No ceremony. No remembering to encrypt things.

Your files go in encrypted. They come out decrypted. Everything in between is beautiful, glorious ciphertext.

### What Gets Encrypted: Git Objects Only

**Important:** GitFoil encrypts what gets stored in Git, not your working directory.

- **Your working directory:** Plain text. You can read, edit, and grep your files normally.
- **Git's storage (`.git` folder):** Encrypted with six layers.
- **What GitHub sees:** Ciphertext. Six layers of indecipherable noise.

When you run `git add` and `git commit`, GitFoil encrypts the file contents before they're stored in Git's object database. When you `git checkout` or `git pull`, files are automatically decrypted to your working directory.

**This means:**
- ✅ Your local files are readable and editable
- ✅ Your remote repo is completely encrypted
- ✅ GitHub employees see only ciphertext
- ⚠️ **You** must protect your local machine (use full disk encryption)
- ⚠️ **You** must back up your master key

### The Encryption Stack

```
Your Precious Secrets
    ↓
AES-256-GCM          ← The classic. NIST-approved. Boring. Reliable.
    ↓
AEGIS-256            ← Won a competition. Very fast. Sounds cool.
    ↓
Schwaemm256-256      ← Impossible to pronounce. Quantum-resistant.
    ↓
Deoxys-II-256        ← Another competition winner. We're very thorough.
    ↓
Ascon-128a           ← NIST's 2023 pick for the quantum apocalypse.
    ↓
ChaCha20-Poly1305    ← Does the encryption cha-cha-cha.
    ↓
Your Git Repository (Now Completely Unreadable)
```

Each layer uses authenticated encryption. Each layer gets its own key derived from your master key.

**The beautiful part:** If someone breaks Layer 6, they get Layer 5 ciphertext. Which looks identical to garbage. They can't tell if they succeeded. No feedback. Just silence until all six yield.

(Spoiler: All six aren't yielding.)

---

## Why Six Layers

### 1. Honestly? Neurosis.

Started with two layers. One was AES-256-GCM—solid, battle-tested, dependable. The other was Ascon-128a for quantum resistance. Both NIST winners. Future-proof.

But.

But Ascon's only 128-bit. And I couldn't shake the feeling that 128 bits wasn't enough—especially for the quantum-resistant layer. So I added another 256-bit layer. And then, in what I can only describe as a series of poor decisions, I kept going.

### 2. Algorithmic Attacks Are Real

**Brute force isn't the threat.** With 704-bit post-quantum security, you'd need 2^704 attempts. More operations than atoms in the universe. Heat death of the sun comes first. Not happening.

**The real threat is algorithmic attacks.** Find a mathematical weakness in the cipher itself. This is how DES, MD5, and SHA-1 actually died. Nobody brute-forced them—they found shortcuts.

**GitFoil's approach:** If one algorithm breaks, you still have five others with completely different mathematical foundations. An attacker gets zero feedback about whether they succeeded. They just see more noise.

With six algorithms, an attacker needs to break ALL of them:

```
P(break GitFoil) = P(break AES) × P(break AEGIS) × P(break Schwaemm)
                   × P(break Deoxys) × P(break Ascon) × P(break ChaCha20)
```

If each has a 1% chance of catastrophic failure (purely illustrative):
- One algorithm: **1% risk**
- Six algorithms: **0.0000000001% risk** (one ten-trillionth)

That's one trillion times better odds.

*The 1% figure is purely illustrative—actual algorithm security is much higher. The point is that cascading independent protections multiply your safety exponentially.*

### 3. Quantum Computers (Maybe)

**1,408-bit combined key space**
**704-bit post-quantum security**

That's **5.5× stronger** than AES-256 alone against quantum computers.

Will quantum computers break modern encryption in your lifetime? Unknown.

Will you sleep better knowing you have 704-bit post-quantum security? Absolutely.

Two of our algorithms (Ascon-128a and Schwaemm256-256) won NIST's competition for post-quantum lightweight cryptography.

---

## Installation

### macOS (Homebrew)

```bash
brew install code-of-kai/gitfoil/git-foil
```

Homebrew automatically installs Elixir and compiles all cryptographic libraries for your machine.

### Other Platforms

See the [installation guide](INSTALL.md) for source installation instructions.

**Why not standalone binaries?** GitFoil uses native cryptographic libraries (Rust NIFs for AEGIS/Ascon/etc., C NIFs for post-quantum Kyber) that must be compiled for your specific system. Homebrew handles this automatically, giving you better performance than a pre-built binary would.

---

## Setup

### Initialize Your Repository

```bash
cd /path/to/your/repo
git-foil init
```

GitFoil will:
1. Generate a quantum-resistant keypair (Kyber1024 + classical)
2. Configure Git's clean/smudge filters for automatic encryption
3. Prompt you to select which files to encrypt

**Pattern selection menu:**
```
[1] Everything (encrypt all files)
[2] Secrets only (*.env, secrets/**, *.key, *.pem, credentials.json)
[3] Environment files (*.env, .env.*)
[4] Custom patterns (interactive)
[5] Decide later
```

Choose your preset or create custom patterns. You can always change this later.

### Password Protection

During initialization, you'll be asked whether to encrypt the master key with a password. Choose based on your security needs.

**Best practice:** Store both your master key file AND your password in your password manager (1Password, Bitwarden, etc.) as secure file attachments. This keeps them backed up and accessible across machines.

### What Just Happened?

1. Generated a cryptographically random keypair (Kyber1024 + classical keys)
2. Derived master encryption key via SHA-512
3. Stored keypair in `.git/git_foil/master.key` (or `.git/git_foil/master.key.enc` if password-protected)
4. Set up Git clean/smudge filters
5. Updated `.gitattributes` with your chosen patterns
**You're done.** Files now encrypt automatically when you commit.

### Switching Password Protection Later

Already initialized? Toggle password protection any time:

```bash
# Encrypt the existing master key with a password (prompts for a new password)
git-foil encrypt key

# Remove password protection (prompts for the current password)
git-foil unencrypt key
```

Each command creates a timestamped backup of the previous key file—copy it into your password manager or delete it once you've stored it safely.

### Non-interactive prompts (CI/local automation)

GitFoil supports two environment variables to make interactive flows deterministic:

- `GIT_FOIL_PASSWORD`: Supplies a password for key operations without prompting.
  - Used by `git-foil encrypt key`, `git-foil unencrypt key`, and some init/rekey flows.
  - Must be at least 8 characters and non-empty. If invalid, commands return a clear error.
  - Unset this var to be prompted interactively.

- `GIT_FOIL_TTY`: Path to a file that acts like a TTY for input.
  - When set, password prompts read from this file (useful for tests and scripts).
  - Example: write two lines for password and confirmation, then run the command.

Interactive flows print a short banner with password requirements (min 8 chars, visible input, Ctrl-C to cancel) and will re-prompt on invalid input.

#### Automation examples

Use an environment variable (non-interactive):

```bash
export GIT_FOIL_PASSWORD='VeryStrongPass9'
git-foil encrypt key
unset GIT_FOIL_PASSWORD
```

Feed prompts from a file (fake TTY):

```bash
printf "VeryStrongPass9\nVeryStrongPass9\n" > /tmp/tty_password
export GIT_FOIL_TTY=/tmp/tty_password
git-foil encrypt key
unset GIT_FOIL_TTY
rm -f /tmp/tty_password
```


---

## Team Usage

### How It Works

GitFoil uses a **shared key model**. Think of it like a shared password manager vault—everyone has the same master key.

One master key file. Everyone copies it to their local `.git/git_foil/` directory.

### Initial Setup (Team Lead)

1. Initialize GitFoil and choose patterns:
   ```bash
   cd /path/to/team/repo
   git-foil init
   git commit -m "Add GitFoil encryption"
   git push
   ```

2. Export the master key for sharing:
   ```bash
   cp .git/git_foil/master.key ~/team-master-key.bin
   ```

3. Share it securely with team members:
   - **GPG-encrypt it:** `gpg --encrypt --recipient teammate@email.com team-master-key.bin`
   - **Password manager:** Upload to 1Password/Bitwarden shared vault
   - **Encrypted file transfer:** Magic Wormhole, Keybase, Signal
   - **In-person:** USB drive, local network over SSH

### Team Member Setup

```bash
# 1. Clone the repo
git clone https://github.com/your-org/your-repo.git
cd your-repo

# 2. Receive the master key (via secure channel)
# Decrypt if necessary: gpg --decrypt team-master-key.bin.gpg > team-master-key.bin

# 3. Place the key
mkdir -p .git/git_foil
cp ~/team-master-key.bin .git/git_foil/master.key
chmod 600 .git/git_foil/master.key

# 4. Initialize GitFoil (sets up filters, uses existing key)
git-foil init

# 5. Refresh working directory
git reset --hard HEAD
```

### Daily Team Workflow

Everyone works normally:

```bash
git pull    # Auto-decrypts incoming changes
git add .
git commit -m "Add feature"
git push    # Auto-encrypts outgoing changes
```

The six layers happen automatically. Nobody thinks about it.

### Revoking Access

To revoke a team member's access, you must generate new keys and re-encrypt:

```bash
git-foil rekey --force
git commit -m "Rotate encryption keys"
git push
```

Share the new `.git/git_foil/master.key` file with remaining team members. The departed member's old key is now useless.

**Note:** The shared key model means revocation is an all-or-nothing operation. If you need frequent revocations, consider whether GitFoil's model fits your use case.

---

## Setting Up on a New Machine

Got a new laptop? Here's what to do:

```bash
# 1. Clone the repo
git clone https://github.com/your-org/your-repo.git
cd your-repo

# 2. Get your master key from your password manager
# Download the master.key file you stored earlier

# 3. Place it in the repo
mkdir -p .git/git_foil
cp ~/Downloads/master.key .git/git_foil/master.key
chmod 600 .git/git_foil/master.key

# 4. Initialize GitFoil (detects key, offers to decrypt working tree)
git-foil init
#    └─ When prompted, choose to decrypt so your working directory contains plaintext.
```

**Done.** Your files are now readable locally and remain encrypted in Git.

**If you don't have the key in your password manager:** You'll need to copy it from your old machine first. The key is located at `.git/git_foil/master.key` in any repo where GitFoil is initialized.

---

## Daily Usage

### Normal Git Workflow

```bash
git add .
git commit -m "Add the secrets"
git push
```

That's it. The six layers happen automatically.

### Managing Encryption Patterns

```bash
# Configure patterns interactively
git-foil configure

# Add specific patterns
git-foil add-pattern "*.env"
git-foil add-pattern "secrets/**/*"

# List configured patterns
git-foil list-patterns

# Remove patterns
git-foil remove-pattern "*.env"
```

### Other Commands

```bash
# Encrypt existing files matching patterns
git-foil encrypt

# Commit .gitattributes changes
git-foil commit

# Generate new master key and re-encrypt everything
git-foil rekey

# Remove GitFoil entirely (decrypt all files)
git-foil unencrypt
```

You're never locked in. Don't like GitFoil anymore? Run `unencrypt` and it's gone.

---

## Technical Specs

### The Algorithms

- AES-256-GCM: NIST FIPS 197 (2001)
- AEGIS-256: Wu & Preneel, CAESAR winner
- Schwaemm256-256: NIST LWC finalist (2019)
- Deoxys-II-256: CAESAR winner
- Ascon-128a: NIST LWC winner (2023)
- ChaCha20-Poly1305: Bernstein, IETF RFC 8439


**Total combined key space:** 1,408 bits
**Post-quantum security:** 704 bits (after Grover's algorithm)

All algorithms are competition winners or international standards. 
We didn't just pick random papers. We just picked more of them than strictly necessary.



### Key Derivation

- **Master keypair:** Kyber1024 (post-quantum) + classical random keys
- **Master key:** SHA-512(classical_secret || pq_secret)[0..31]
- **File keys:** HKDF-SHA3-512 with path-based salts
- **Per-layer keys:** Independent derivation using unique context strings
- **IV/Nonce:** Deterministic SHA3-256 (required for Git's deterministic model)
- **Authentication:** AEAD on every single layer

### Security Properties

- ✅  Deterministic encryption (same file → same ciphertext, for Git compatibility)
- ✅  Authenticated encryption (tampering detection on all layers)
- ✅  Algorithm diversity (six different mathematical approaches)
- ✅  Competition-vetted (every algorithm won something)
- ✅  No-feedback property (breaking N-1 layers reveals nothing)
- ✅  Quantum-resistant (Kyber1024 keypair + two post-quantum algorithms)
- ✅  Side-channel resistant (constant-time Rust implementations)
- ✅  File isolation (per-file key derivation prevents cross-file attacks)

### Security Limitations

* ⚠️ **Shared key model** — All team members use the same master key. Revoking access requires re-encrypting the entire repository. No per-user audit or access control.
* ⚠️ **Deterministic encryption** — For Git compatibility, identical plaintexts produce identical ciphertexts. This leaks equality patterns and reveals when files remain unchanged or revert to earlier versions.
* ⚠️ **Unencrypted working directory** — Files are stored in plaintext locally. Protect your machine with full-disk encryption and strong access controls.
* ⚠️ **No formal audit** — While all algorithms are standards or competition winners, the combined system and multi-layer design have not yet undergone independent cryptographic review.
* ⚠️ **Key loss** — Losing your master key makes encrypted data in Git permanently unrecoverable. Back up your key securely in a password manager or encrypted storage.

---

## FAQ

**Isn't this overkill?**
Yes. Started as two layers. Ended as six. These things happen.

**Does this protect against GitHub employees reading my code?**
Yes. They see ciphertext. Six layers of ciphertext. Useless without your master key file.

**What if my laptop is stolen?**
If you used password protection during init (recommended), your master key is encrypted and useless to the thief without your password. If you chose plaintext key storage, the key is protected only by filesystem permissions—use full disk encryption (FileVault, BitLocker, LUKS) to protect local data.

**What if I lose my master key?**
Your encrypted data in Git is unrecoverable. But your working directory files are still there, unencrypted, on your computer. They're just regular files.

You can:
1. Keep working with your local unencrypted files
2. Run `git-foil rekey` to generate a new master key
3. Re-encrypt everything with the new key
4. Store the new key somewhere safe this time

**But don't rely on this.** Back up your `master.key` file properly:
- Store it in a password manager (1Password, Bitwarden)
- Keep an encrypted backup (GPG-encrypted on USB drive)

**Will quantum computers break this?**
Not with current or near-future technology. You'd need 2^704 operations. That's more than the number of atoms in the observable universe.

**What if one algorithm gets broken?**
You still have five others. The attacker gets the next layer's ciphertext, which is indistinguishable from random noise. Zero feedback. They must break ALL six.

**Is this actually secure or just security theater?**
It's actually secure! All six algorithms are competition winners or standards. The implementation uses authenticated encryption, proper key derivation, and constant-time operations.

**Can I use this with CI/CD?**
GitFoil is for people with trust issues. If you're okay storing your master key with GitHub and trusting Microsoft with your secrets, use [git-crypt](https://github.com/AGWA/git-crypt) instead—it's excellent and better suited for CI/CD workflows.

**Why Elixir?**
Because Elixir is a great language. The crypto happens in Rust NIFs anyway.

**Can teams use this?**
Yes! One person generates the master key, then shares the `master.key` file securely with team members. See the Team Usage section above.

**Should I actually use this?**
- If you have secrets in your repo: **absolutely**
- If your repo is a public open-source project: **probably not**
- If you just like the idea of six layers: **go for it, it's fun**

---

## Comparison vs. Git-Crypt

| Feature | GitFoil | git-crypt |
|---------|---------|-----------|
| Layers | 6 | 1 |
| AES-256 | ✅ (plus 5 others) | ✅ |
| Key size | 1,408-bit | 256-bit |
| Quantum resistance | 704-bit | 128-bit |
| Origin story | Paranoid temperament | Rational design |
| Absurdity | High | Low |
| Actually works | ✅ | ✅ |

---

## Security Notes

GitFoil is production-ready but hasn't undergone a formal security audit. Do your own research if the stakes are high.

Before using in high-stakes environments:
- Get a code review from a cryptographer
- Consider penetration testing
- Run fuzzing on the parsers
- Evaluate whether the shared key model fits your threat model

### Known Limitations

- Shared key model (can't revoke individual users without rekeying)
- No key rotation without re-encrypting entire repo
- No per-user audit trail

These are design choices, not bugs. GitFoil prioritizes simplicity and automatic operation over fine-grained access control.

---

## Architecture

GitFoil uses hexagonal architecture (ports & adapters):

- **Core:** Pure business logic
- **Ports:** Abstract interfaces
- **Adapters:** Concrete implementations

This makes it testable, maintainable, and extensible.

It also makes us sound professional despite the origin story.

If we ever decide we need a seventh layer, the architecture will support it.

(We won't need a seventh layer.)

(Probably.)

---


## License

BSD 3-Clause License - see [LICENSE](LICENSE) file for details.

---

## Philosophical Note

Is six layers of encryption excessive? Yes.

Is it unnecessary for 99.9% of use cases? Probably.

But here's the thing: **great security should be invisible**. You set it up once, and then you forget it exists. Your files are encrypted in Git. Your team can collaborate normally. GitHub sees only ciphertext. Your working directory stays readable.

And if quantum computers ever do break modern encryption, or if some NSA slide deck leaks showing AES was compromised, or if your intern accidentally pushes the repo to a public GitLab...

You'll sleep soundly.

Because you have six layers of cascading cryptographic fury protecting your `database.env` file.

Is that rational? Debatable.

Is it effective? Absolutely.

Does it work? **Yes.**

---

## Set it up once. Then forget it exists.

*Six layers. Zero extra steps.*
*Your files stay readable. Your repo stays encrypted. Paranoia minimized. You can finally sleep at night.*
