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

If each has a 1% chance of catastrophic failure:
- One algorithm: **1% risk**
- Six algorithms: **0.000000000001% risk**

That's one trillion times better odds.

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

During initialization, GitFoil will ask:

```
🔐  Protect your master key with a password?

   YES → Stores the key encrypted on disk.
         Requires the password to unlock the repository.
   NO  → Stores the key in plaintext (.git/git_foil/master.key).
         Anyone with that file can decrypt your history.

Encrypt the master key with a password? [y/N]:
```

**With password protection (YES):**
- Master key encrypted with PBKDF2 (600K iterations) + AES-256-GCM
- Stored in `.git/git_foil/master.key.enc`
- Requires password to decrypt files

**Without password protection (NO):**
- Master key stored in plaintext in `.git/git_foil/master.key`
- Protected only by filesystem permissions (like SSH keys)
- No password needed to decrypt files

**When to use password protection:**
- ✅ Laptop travels frequently
- ✅ Highly sensitive projects
- ✅ Shared workstations
- ✅ Compliance requirements

**Note:** You can bypass the prompt with `git-foil init --password` or `git-foil init --no-password` flags.

### What Just Happened?

1. Generated a cryptographically random keypair (Kyber1024 + classical keys)
2. Derived master encryption key via SHA-512
3. Stored keypair in `.git/git_foil/master.key` (or `.git/git_foil/master.key.enc` if password-protected)
4. Set up Git clean/smudge filters
5. Updated `.gitattributes` with your chosen patterns

**You're done.** Files now encrypt automatically when you commit.

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

### 1. Back Up Your Key (On Old Machine)

```bash
cd /path/to/repo
cp .git/git_foil/master.key ~/master-key-backup.bin

# Store it securely:
# - Encrypted USB drive
# - Password manager (as secure file attachment)
# - GPG-encrypted: gpg --encrypt --recipient your@email.com master-key-backup.bin
```

**DO NOT:**
- ❌ Email the key unencrypted
- ❌ Commit it to the repository
- ❌ Store it in plaintext on cloud storage

### 2. Setup on New Machine

```bash
# Clone the repo
git clone https://github.com/your-org/your-repo.git
cd your-repo

# Restore your key
mkdir -p .git/git_foil
cp ~/master-key-backup.bin .git/git_foil/master.key
chmod 600 .git/git_foil/master.key

# Initialize GitFoil (detects existing key, configures filters)
git-foil init

# Refresh working directory
git reset --hard HEAD
```

Your encrypted files decrypt and appear as plain text.

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

### The Stack

| Layer | Algorithm | Key | Type | Pedigree |
|-------|-----------|-----|------|----------|
| 1 | AES-256-GCM | 256-bit | Block cipher | NIST standard since 2001 |
| 2 | AEGIS-256 | 256-bit | AES-based AEAD | CAESAR winner |
| 3 | Schwaemm256-256 | 256-bit | Sponge | NIST finalist |
| 4 | Deoxys-II-256 | 256-bit | Tweakable block | CAESAR winner |
| 5 | Ascon-128a | 128-bit | Sponge | **NIST winner (2023)** |
| 6 | ChaCha20-Poly1305 | 256-bit | Stream cipher | IETF standard |

**Total combined key space:** 1,408 bits
**Post-quantum security:** 704 bits (after Grover's algorithm)

All algorithms are competition winners or IETF/NIST standards.

### Key Derivation

- **Master keypair:** Kyber1024 (post-quantum) + classical random keys
- **Master key:** SHA-512(classical_secret || pq_secret)[0..31]
- **File keys:** HKDF-SHA3-512 with path-based salts
- **Per-layer keys:** Independent derivation using unique context strings
- **IV/Nonce:** Deterministic SHA3-256 (required for Git's deterministic model)
- **Authentication:** AEAD on every single layer

### Security Properties

✅ Deterministic encryption (same file → same ciphertext, for Git compatibility)
✅ Authenticated encryption (tampering detection on all layers)
✅ Algorithm diversity (six different mathematical approaches)
✅ Competition-vetted (every algorithm won something)
✅ No-feedback property (breaking N-1 layers reveals nothing)
✅ Quantum-resistant (Kyber1024 keypair + two post-quantum algorithms)
✅ Side-channel resistant (constant-time Rust implementations)
✅ File isolation (per-file key derivation prevents cross-file attacks)

### Security Limitations

⚠️ **Master key storage** - By default, `.git/git_foil/master.key` is stored as plaintext binary on disk, protected only by filesystem permissions (0600). Use `git-foil init --password` for additional encryption.

⚠️ **Shared key model** - All team members use the same master key file. Can't revoke individual access without re-keying the entire repository.

**Security Model:** GitFoil's security model is similar to SSH keys—unencrypted files protected by filesystem permissions (or optionally password-encrypted). Full disk encryption is recommended for comprehensive local security.

### Performance

Built in Elixir with **Rust NIFs** for the actual crypto.

**On a laptop:**
- Encrypt 1,000 files: ~2 seconds
- Decrypt 1,000 files: ~2 seconds
- Throughput: ~100-200 MB/s per file

Yes, even with six layers. Turns out when you're neurotic about security, you're also neurotic about performance.

**Features:**
- Automatic CPU core detection
- Parallel encryption during `git add`
- Progress bars for large repos
- Intelligent batching with back-pressure
- Retry logic for Git lock contention

You won't notice it happening. Which is exactly the point.

---

## FAQ

**Isn't this overkill?**
Yes. Started as two layers. Ended as six. These things happen.

**Does this protect against GitHub employees reading my code?**
Yes. They see ciphertext. Six layers of ciphertext. Useless without your master key file.

**What about laptop theft?**
GitFoil doesn't protect against that. Your `master.key` file is unencrypted on disk by default (like SSH keys). Use full disk encryption (FileVault, BitLocker, LUKS) to protect local data and keys. Or use `--password` flag for encrypted key storage.

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
- Treat it like SSH private keys

**Will quantum computers break this?**
Not with current or near-future technology. You'd need 2^704 operations. That's more than the number of atoms in the observable universe.

**What if one algorithm gets broken?**
You still have five others. The attacker gets the next layer's ciphertext, which is indistinguishable from random noise. Zero feedback. They must break ALL six.

**Is this actually secure or just security theater?**
It's actually secure! All six algorithms are competition winners or standards. The implementation uses authenticated encryption, proper key derivation, and constant-time operations.

**Can I use this with CI/CD?**
GitFoil is for people with trust issues. If you're okay storing your master key with GitHub and trusting Microsoft with your secrets, use [git-crypt](https://github.com/AGWA/git-crypt) instead—it's excellent and better suited for CI/CD workflows.

**Why Elixir?**
Because it's good at concurrent processing. The crypto happens in Rust NIFs anyway.

**Can teams use this?**
Yes! One person generates the master key, then shares the `master.key` file securely with team members. See the Team Usage section above.

**Should I actually use this?**
- If you have secrets in your repo: **absolutely**
- If it's a public open-source project: **probably not**
- If you just like the idea of six layers: **go for it, it's fun**

---

## Comparison vs. Git-Crypt

| Feature | GitFoil | git-crypt |
|---------|---------|-----------|
| Layers | 6 | 1 |
| AES-256 | ✅ (plus 5 others) | ✅ |
| Key size | 1,408-bit | 256-bit |
| Quantum resistance | 704-bit | 128-bit |
| Origin story | Neurosis about 128-bit keys | Rational design |
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

- Master key stored unencrypted on disk by default (like SSH keys—use full disk encryption or `--password` flag)
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

## Stats

- ~6,800 lines of Elixir
- 5 Rust NIFs for crypto
- 18 integration tests
- Real Git operations in tests
- One-command Homebrew installation
- Compiles natively for optimal performance
- 6-layer encryption that exists because of questionable decision-making

---

## Credits

Built on the shoulders of giants (who used more reasonable numbers of layers):

- **Elixir/Erlang** - Because concurrency is nice
- **Rust** - Because memory safety is nice
- **Homebrew** - Because simple installation is nice
- **NIST/CAESAR competitions** - Because vetted crypto is nice
- **Kyber1024** - Post-quantum key encapsulation
- **Coffee** - Because building this was ridiculous

### Algorithm Credits

- AES-256-GCM: NIST FIPS 197 (2001)
- AEGIS-256: Wu & Preneel, CAESAR winner
- Schwaemm256-256: NIST LWC finalist (2019)
- Deoxys-II-256: CAESAR winner
- Ascon-128a: NIST LWC winner (2023)
- ChaCha20-Poly1305: Bernstein, IETF RFC 8439

All algorithms are competition winners or international standards. We didn't just pick random papers. We just picked more of them than necessary.

---

## License

BSD 3-Clause License

Copyright (c) 2025, GitFoil Contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

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

*Six layers. Zero extra steps. Paranoia minimized.*
*Your files stay readable. Your repo stays encrypted. You can finally sleep at night.*
