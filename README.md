# GitFoil

Six layers of encryption because you're a little paranoid, you've accepted that, and you need to sleep at night.

Quantum-resistant security that piggybacks on Git. Set it up once, then sleep soundly knowing it's so absurdly overbuilt that your paranoia finally shuts up.

![GitFoil Logo](docs/images/GitFoil.jpg)

---

## The Problem

Look, we both know you're paranoid.

You're convinced AES-256 has a backdoor, aren't you? You read that Hacker News thread about quantum computers. You saw that leaked slide deck about agencies hoarding zero-days. You don't trust Microsoft with your code. You definitely don't trust that intern who keeps committing API keys.

Are you being paranoid?

Yes. Absolutely.

Is it justified?

Your therapist says no. History says maybe.

So what now?

Six layers of encryption, that's what.

___

## The Solution (That Nobody Asked For)

What if we just... kept encrypting?

Like, what if we encrypted it. Then encrypted *that*. Then did it four more times.

With six completely different algorithms. Six derived keys. So that breaking one gives you... the next layer of indecipherable noise.

Would that be overkill?

Yes.

Would it be *absurdly* overkill?

Also yes.

Would you sleep better at night knowing your `database.env` file is wrapped in 1,408 bits of cascading cryptographic fury?

**Finally, yes.**

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

GitFoil piggybacks on your normal workflow. No extra commands. No ceremony. No remembering to encrypt things.

Your files go in encrypted. They come out decrypted. Everything in between is beautiful, glorious ciphertext that would make a cryptographer weep.

Or laugh. Probably laugh.

---

## The Encryption Stack (Yes, Really)

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
ChaCha20-Poly1305    ← Does the encryption cha-cha-cha. Takes two to tango, six to secure.
    ↓
Your Git Repository (Now Completely Unreadable)
```

Each layer uses authenticated encryption. Each layer gets its own key derived from your master key.

**Here's the beautiful part:** If someone breaks Layer 6, they get Layer 5 ciphertext. Which looks identical to garbage. They can't tell if they succeeded. It's like a safe where no lock clicks. Just silence until all six yield.

(Spoiler: All six aren't yielding.)

---

## Why Six Layers (A Reasonable Question)

### 1. Honestly? Neurosis.

Started with two layers. One was AES-256-GCM—solid, battle-tested, dependable. The other was Ascon-128a for quantum resistance. Both NIST winners. Future-proof.

But.

But Ascon's only 128-bit. And I couldn't shake the feeling that 128 bits wasn't enough—especially for the quantum-resistant layer. So I added another 256-bit layer. And then, in what I can only describe as a series of poor decisions, I kept going.

---

## Brute Force vs. Actually Breaking It

**Brute force:** Try every possible key combination until one works.
- With 704-bit post-quantum security, that's 2^704 attempts.
- More operations than atoms in the universe.
- Heat death of the sun comes first.
- Not happening. Even with quantum computers.
  - Even with Grover's algorithm (the best quantum attack), you'd need 2^704 operations to break this.
  - That's approximately 10^212 operations.
  - For context: 2^128 is considered quantum-safe. This is 2^576 times harder.
  - The universe will end. Your encryption won't break.

**Algorithmic attack:** Find a mathematical weakness in the cipher itself.
- Much more realistic threat.
- This is how DES, MD5, and SHA-1 actually died.
- Nobody brute-forced them. Instead, they found shortcuts.

**GitFoil's approach:** If one algorithm breaks, you still have five others with completely different mathematical foundations. An attacker gets zero feedback about whether they succeeded. They just see more noise.

Look, brute force isn't the threat. Algorithmic weaknesses are. DES fell. MD5 fell. SHA-1 fell. They didn't get brute-forced—they had mathematical flaws nobody saw coming.

So yeah, six layers sounds insane. And honestly? Most of this README has been making fun of how absurd it is.

But this part? This part actually makes sense.

When one cipher breaks, you've got five more. That's not paranoia—that's just learning from history.

### The Math

With six algorithms, an attacker needs to break ALL of them:

```
P(break GitFoil) = P(break AES) × P(break AEGIS) × P(break Schwaemm)
                   × P(break Deoxys) × P(break Ascon) × P(break ChaCha20)
```

If each has a 1% chance of catastrophic failure:
- One algorithm: **1% risk**
- Six algorithms: **0.000000000001% risk**

That's one trillion times better odds.

Is this mathematically sound? *Probably!*

Are we overthinking this? *Definitely!*

Are we doing it anyway? **Obviously.**

### 2. Quantum Computers (Maybe)

**1,408-bit combined key space**  
**704-bit post-quantum security**

That's **5.5× stronger** than AES-256 alone against quantum computers.

Will quantum computers break modern encryption in your lifetime? Unknown.

Will you sleep better knowing you have 704-bit post-quantum security? Absolutely.

Two of our algorithms (Ascon-128a and Schwaemm256-256) literally won NIST's competition for post-quantum lightweight cryptography.

Are we ready for the quantum apocalypse? Yes.

Is the quantum apocalypse coming? ¯\\\_(ツ)_/¯

### 3. Because It's Funny

Look, at some point you have to acknowledge the absurdity.

Six layers of encryption for your `TODO.md` file is objectively hilarious (and algorithmic attacks are a real threat).

But also? It works. And it's fast. And it's automatic. And once it's set up, you never think about it again.

So why not?

---

## Technical Specs (For the Nerds)

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
**Layers added due to questionable decision-making:** 4

All algorithms are competition winners or IETF/NIST standards. We didn't just pick random ciphers. Though we did pick more of them than strictly necessary.

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
✅ Probably overcompensating (but functional)

### Security Limitations

⚠️ **Master key storage** - By default, the `.git/git_foil/master.key` file is stored as plaintext binary on disk, protected only by filesystem permissions (0600).

✅ **Password protection available** - Use `git-foil init --password` to encrypt your master key with a password (PBKDF2 + AES-256-GCM). This provides additional protection against stolen laptop scenarios. The encrypted key is stored in `.git/git_foil/master.key.enc` instead.

⚠️ **Shared key model** - All team members use the same master key file. Can't revoke individual team member access without re-keying the entire repository.

**Security Model:** Without password protection, GitFoil's security model is similar to SSH keys—unencrypted files protected by filesystem permissions. With password protection enabled, your master key gains an additional encryption layer, similar to SSH keys with passphrases. Full disk encryption is still recommended for comprehensive local security.

---

## Performance

### Surprisingly Fast

Built in Elixir with **Rust NIFs** for the actual crypto.

**On a laptop:**
- Encrypt 1,000 files: ~2 seconds
- Decrypt 1,000 files: ~2 seconds
- Throughput: ~100-200 MB/s per file

Yes, even with six layers. Turns out when you're neurotic about security, you're also neurotic about performance.

### It Just Works™

- Automatic CPU core detection
- Parallel encryption during `git add`
- Progress bars for large repos
- Intelligent batching with back-pressure
- Retry logic for Git lock contention

You won't notice it happening.

Which is exactly the point.

---

## Setup

### You'll Need

- Git 2.0+
- Elixir 1.18+ (Homebrew installs this automatically)
- A healthy respect for paranoia

### Installation

**Homebrew (macOS, easiest):**

```bash
brew install code-of-kai/gitfoil/git-foil
```

That's it! One command. Homebrew will automatically install Elixir and compile all the cryptographic libraries for your machine.

<details>
<summary><strong>From source (any platform)</strong></summary>

If you don't use Homebrew or are on Linux:

**Requirements:**
- Elixir 1.18+
- Rust 1.70+

```bash
# Clone the repository
git clone https://github.com/code-of-kai/git-foil.git
cd git-foil

# Install dependencies and compile
mix deps.get
mix compile
```

Then add the compiled project to your PATH. See [INSTALL.md](INSTALL.md) for detailed instructions.

**Why not standalone binaries?**

GitFoil uses native cryptographic libraries (Rust NIFs for AEGIS/Ascon/etc., C NIFs for post-quantum Kyber) that need to be compiled for your specific system. Homebrew handles this automatically, compiling everything optimally for your machine. This actually gives you better performance than a pre-built binary would.

</details>

### Initialize Your Repo

**Option 1: Quick setup (no password)**

```bash
cd /path/to/your/precious/repo

git-foil init

# Generates random quantum-resistant keys
# Keys stored in .git/git_foil/master.key (protected by filesystem permissions)
```

**Option 2: Enhanced security (password-protected)**

```bash
cd /path/to/your/precious/repo

git-foil init --password

# Prompts for password (with confirmation)
# Keys stored encrypted in .git/git_foil/master.key.enc
# Uses PBKDF2 (600K iterations) + AES-256-GCM
```

That's it. GitFoil hooks into Git's filter system and vanishes.

### What Just Happened?

1. Generated a cryptographically random keypair (Kyber1024 + classical keys)
2. Derived master encryption key via SHA-512
3. Stored keypair in `.git/git_foil/master.key` (permissions: 0600)
4. Set up Git clean/smudge filters
5. Prompted you to select files to encrypt
6. Updated `.gitattributes`

Now every time you `git add`, files get encrypted.  
Every time you `git checkout`, files get decrypted.

**You never run `git-foil` again.** (Well, almost never - see below.)

### Key Storage

**Without password protection:**
- **Location:** `.git/git_foil/master.key`
- **Format:** Binary keypair (Kyber1024 + classical)
- **Permissions:** 0600 (owner read/write only)
- **Security:** Protected by filesystem permissions only
- **Important:** Back up this file! Without it, you cannot decrypt your files.

**With password protection (`--password` flag):**
- **Location:** `.git/git_foil/master.key.enc`
- **Format:** Encrypted binary keypair
- **Encryption:** PBKDF2-HMAC-SHA512 (600,000 iterations) + AES-256-GCM
- **Permissions:** 0600 (owner read/write only)
- **Security:** Protected by password + filesystem permissions
- **Important:** Remember your password! There is NO password recovery mechanism. Back up your encrypted key file!

### Password Protection Best Practices

**When to use password protection:**
- ✅ Laptop travels frequently (conferences, coffee shops, etc.)
- ✅ Working on highly sensitive projects
- ✅ Shared workstations or multi-user systems
- ✅ Compliance requirements for encrypted key storage
- ✅ You want defense-in-depth (filesystem permissions + encryption)

**When password protection may be optional:**
- Desktop workstation in secure location
- Full disk encryption already enabled (FileVault/BitLocker/LUKS)
- Low-sensitivity personal projects
- Team workflow requires frequent key sharing

**Password recommendations:**
- Minimum 8 characters (enforced by GitFoil)
- Use a password manager to generate and store it
- Consider a passphrase: "correct horse battery staple" style
- Don't reuse passwords from other services

**CI/CD Integration:**
GitFoil supports the `GIT_FOIL_PASSWORD` environment variable for automation:

```bash
# In CI/CD, set the password as an environment variable
export GIT_FOIL_PASSWORD="your-password-from-secrets"

# GitFoil will automatically use it without prompting
git clone your-repo && cd your-repo
git-foil init  # Uses $GIT_FOIL_PASSWORD automatically
```

⚠️ **Security Warning:** Environment variables can leak to debuggers, logs, and other processes running under the same user. The `GIT_FOIL_PASSWORD` variable is **intended for CI/CD systems only**, not for interactive shells on shared systems. For daily use, let GitFoil prompt you for the password instead.

**Migrating between modes:**

```bash
# Add password protection to existing repo
git-foil init --password --force

# Your old plaintext key is automatically backed up
# New encrypted key created at .git/git_foil/master.key.enc
```

---

## Understanding What Gets Encrypted (Important!)

Let's be clear about what GitFoil does and doesn't protect:

### Your Working Directory: Unencrypted

**The files on your computer remain in plain text.**

When you're working on your code, editing `secrets.env` or `api_keys.json`, those files are completely readable on your local machine. You can open them in your editor, grep them, back them up—they're just normal files.

GitFoil doesn't encrypt your working directory. It encrypts what gets stored in Git.

### What Gets Encrypted: Git Objects

When you run `git add` and `git commit`, GitFoil kicks in. It encrypts the file contents before they're stored in Git's internal object database (the `.git` directory). Then when you `git push`, those encrypted Git objects go to GitHub/GitLab/wherever.

**What GitHub sees:** Ciphertext. Six layers of indecipherable noise.

**What you see on your computer:** Your actual code, readable and editable.

### This Means Two Things

**Good news:** If something happens to your remote repo, your local files are fine. They're right there, unencrypted, ready to use. You can back them up, copy them, whatever you want.

**Your responsibility:** Securing your local machine is *your* problem. GitFoil protects your code from GitHub breaches, nosy employees, and government data requests. It doesn't protect your laptop from theft or your hard drive from failure.

**Use full disk encryption.** FileVault on Mac, BitLocker on Windows, LUKS on Linux. GitFoil protects your *remote* repos. Disk encryption protects your *local* files and keys.

**Backup your local files and keys.** GitFoil solves the "external repo security" problem. It doesn't solve the "my laptop died" problem. That's a different problem. Handle it accordingly.

---

## Setting Up On a New Machine

Got a new laptop? Cloning the repo to a new workstation? Here's what to do:

### The Key Insight

GitFoil uses a **shared secret model**. You need the `master.key` file from your original setup. Think of it like an SSH private key - you generate it once, then copy it to any machine where you need access.

### Step 1: Back Up Your Key (On Old Machine)

Before you need it, back up your master key:

```bash
cd /path/to/repo

# Export your master key
cp .git/git_foil/master.key ~/master-key-backup.bin

# Store it securely:
# - Encrypted USB drive
# - Password manager (as secure file attachment)
# - GPG-encrypted: gpg --encrypt --recipient your@email.com master-key-backup.bin
# - Encrypted cloud storage (NOT plaintext Dropbox!)
```

**DO NOT:**
- ❌ Email the key unencrypted
- ❌ Commit it to the repository
- ❌ Store it in plaintext on cloud storage
- ❌ Share it via Slack/Discord without encryption

### Step 2: Clone the Repo (On New Machine)

```bash
git clone https://github.com/your-org/your-repo.git
cd your-repo
```

At this point, if you try to check out encrypted files, Git will fail because the filters aren't set up.

### Step 3: Restore Your Key

```bash
# Create the directory
mkdir -p .git/git_foil

# Copy your backed-up master key
cp ~/master-key-backup.bin .git/git_foil/master.key

# Set correct permissions
chmod 600 .git/git_foil/master.key
```

### Step 4: Initialize GitFoil

```bash
# This sets up the Git filters and detects the existing key
git-foil init

# Since master.key already exists, it won't generate a new one
# It just configures the Git filters
```

### Step 5: Refresh Your Working Directory

```bash
# Force Git to re-run the smudge filter on all files
git reset --hard HEAD
```

Your encrypted files decrypt and appear as plain text in your working directory.

**That's it.** You're ready to work.

### Important Notes

- The `master.key` file is the same cryptographic key you use on all your machines
- Same key = same decrypted files
- Back up this key file somewhere secure (encrypted password manager, GPG-encrypted backup, etc.)
- If you lose the key, your encrypted data is unrecoverable

---

## Team Usage

### How Team Encryption Works

GitFoil uses a **shared key model** for teams. Think of it like a shared password manager vault - everyone has the same master key.

**One master key file.** Everyone copies it to their local `.git/git_foil/` directory. Everyone can encrypt and decrypt with the same keys.

### Initial Setup (Team Lead)

1. **One person** initializes GitFoil:
   ```bash
   cd /path/to/team/repo
   git-foil init
   
   # Selects files to encrypt
   git add .gitattributes
   git commit -m "Add GitFoil encryption"
   git push
   ```

2. **Export the master key** for sharing:
   ```bash
   cp .git/git_foil/master.key ~/team-master-key.bin
   ```

3. **Share it securely** with team members:

   **Good options:**
   - **GPG-encrypt it:**
     ```bash
     gpg --encrypt --recipient teammate@email.com team-master-key.bin
     # Send the .gpg file via any channel
     ```
   
   - **Password manager:** Upload to 1Password shared vault, Bitwarden organization, LastPass shared folder
   
   - **Encrypted file transfer:** Magic Wormhole (`wormhole send`), Keybase, Signal file attachment
   
   - **In-person:** USB drive, local network over SSH

### Team Member Setup

Each team member receiving the key:

```bash
# 1. Clone the repo
git clone https://github.com/your-org/your-repo.git
cd your-repo

# 2. Receive the master key file (via secure channel above)
#    Decrypt if necessary: gpg --decrypt team-master-key.bin.gpg > team-master-key.bin

# 3. Place the key
mkdir -p .git/git_foil
cp ~/team-master-key.bin .git/git_foil/master.key
chmod 600 .git/git_foil/master.key

# 4. Initialize GitFoil (sets up filters, doesn't generate new key)
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

### What's Shared

✅ **The same `master.key` file** - copied to each team member's local `.git/git_foil/` directory  
✅ **The same encryption keys** - everyone can decrypt each other's commits  
✅ **The `.gitattributes` file** - defines which files are encrypted (committed to repo)

❌ **NOT shared via Git** - the `master.key` file itself (never committed, always stays local)

### Team Security Considerations

**Single shared key means:**
- ✅ Simple setup - just copy one file
- ✅ Everyone has access - easy collaboration
- ❌ Can't revoke individual team members - if someone leaves, you'd need to generate a new key and re-encrypt everything
- ❌ No per-user audit trail - can't tell who encrypted/decrypted files
- ❌ One compromised laptop = entire team must rotate keys

**This is fine for:**
- Small trusted teams
- Teams with stable membership
- Internal projects with trusted collaborators

**This is NOT ideal for:**
- Large teams with frequent turnover
- Projects requiring per-user access control
- Situations requiring individual revocation

---

## Usage

### Daily Workflow

```bash
git add .
git commit -m "Add the secrets"
git push
```

That's it. The six layers happen automatically.

Files are encrypted in commits. Files stay decrypted in your working directory. You never think about it.

### Core Commands

```bash
# Initialize GitFoil in a repo (one-time setup)
git-foil init

# Check current configuration
git-foil config

# See which files are encrypted
git-foil status
```

### Managing What Gets Encrypted

```bash
# Add patterns to encrypt
git-foil pattern add "*.env"
git-foil pattern add "secrets/**/*"

# List encrypted patterns
git-foil pattern list

# Remove patterns
git-foil pattern remove "*.env"
```

### Advanced Operations

```bash
# Unencrypt all files (removes GitFoil entirely)
git-foil unencrypt

# Re-encrypt with the same master key
# (Useful after changing encryption patterns)
git-foil recrypt

# Generate a new master key and re-encrypt everything
# (Useful when team member leaves or key is compromised)
git-foil rekey
```

These commands exist so you're never locked in. Don't like GitFoil anymore? Run `unencrypt` and it's gone. Want to change your patterns? Run `recrypt`. Need a fresh master key? Run `rekey`.

**You're always in control.**

---

## FAQ

**Isn't this overkill?**  
Yes. Started as two layers. Ended as six. These things happen.

**Did you really add four extra layers because one was 128-bit?**  
Look, we all have our processes.

**Was it because one was a tiny 128-bit and felt inadequate?**  
...Hey! That's none of your business!

**Does this protect against GitHub employees reading my code?**  
Yes. They see ciphertext. Six layers of ciphertext. Useless without your master key file.

**What about laptop theft?**  
GitFoil doesn't protect against that. Your `master.key` file is unencrypted on disk (like an SSH private key). Use full disk encryption (FileVault, BitLocker, LUKS) to protect local data and keys.

**What if I lose my master key?**  
Your encrypted data in the Git repository is unrecoverable. That's not a bug, it's a feature.

But here's the important part: **your working directory files are still there, unencrypted, on your computer.** They're just regular files. You haven't lost your code, you've just lost the ability to decrypt what's in your Git history and remote repo.

If this happens, you can:
1. Keep working with your local unencrypted files (they're fine)
2. Run `git-foil rekey` to generate a new master key
3. Re-encrypt everything with the new key
4. Store the new key somewhere safe this time, you naughty boy

**But don't rely on this as a backup strategy.** Back up your `master.key` file properly:
- Store it in a password manager (1Password, Bitwarden, etc.)
- Keep an encrypted backup (GPG-encrypted on a USB drive)
- Treat it like you'd treat your SSH private keys

Here's the thing: **your biggest threat is yourself.** You're way more likely to lose your master key than you are to have some three-letter agency break into your repo to steal your Slack clone or todo app.

The NSA doesn't care about your code. But you will care if you lose your key and have to rekey everything.

**Will quantum computers break this?**  
Not with current or near-future technology. You'd need 2^704 operations. That's more than the number of atoms in the observable universe. You're fine.

**What if one algorithm gets broken?**  
You still have five others. The attacker gets the next layer's ciphertext, which is indistinguishable from random noise. They get zero feedback. They must break ALL six.

**Is this actually secure or just security theater?**  
It's actually secure! All six algorithms are competition winners or standards. The implementation uses authenticated encryption, proper key derivation, and constant-time operations. We just acknowledge that it started from a slightly absurd place.

**Can I use this with CI/CD?**  
I'm... very disappointed in you. I thought you were as paranoid as me.

If you're okay storing your master key with GitHub and trusting Microsoft with your secrets, then GitFoil probably isn't for you. You should use [git-crypt](https://github.com/AGWA/git-crypt) instead—it's excellent and better suited for CI/CD workflows.

GitFoil is for people with trust issues.

**Why Elixir?**  
Because it's good at concurrent processing. The crypto happens in Rust NIFs anyway. And honestly after adding six layers, the language choice seemed less neurotic by comparison.

**Why Rust NIFs?**  
Fast, memory-safe, side-channel resistant, and compiles to native code. Perfect for crypto.

**What's with the ChaCha20 layer?**  
ChaCha20-Poly1305 is an IETF standard designed by Daniel Bernstein. It's a stream cipher that's incredibly fast and secure. The name sounds like a dance, but it's actually excellent cryptography. Your secrets are now protected by an algorithm that goes cha-cha-cha. And yes, that's hilarious.

**Can teams use this?**  
Yes! One person generates the master key, then shares the `master.key` file securely (GPG-encrypted, password manager, etc.) with team members. Everyone copies it to their local `.git/git_foil/` directory. See the Team Usage section above.

**Can I revoke access for a team member who left?**  
Yes, but it requires re-keying the entire repository. Run `git-foil rekey --force` to generate a new master key and re-encrypt all files. Then share the new `master.key` file with remaining team members (but not the person who left).

The old key is automatically backed up to `.git/git_foil/master.key.backup.<timestamp>` in case you need it.

**Steps:**
1. Run `git-foil rekey --force` (generates new keys)
2. Commit and push the re-encrypted files
3. Share the new `.git/git_foil/master.key` securely with remaining team members
4. Team members place the new key in their `.git/git_foil/` directory
5. The departed team member's old key is now useless

The shared key model means this is an all-or-nothing operation. If you need frequent revocations, consider whether GitFoil's shared key model fits your use case, or look into alternatives like git-secret with per-user GPG keys.

**Should I actually use this?**  
- If you have secrets in your repo: **absolutely**
- If it's a public open-source project: **how would people fork it? You haven't thought this through, have you?**
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
- Maybe ask yourself if you really need six layers (depends on your relationship with paranoia)

Or just use it anyway. We're not your boss.

### Known Limitations

- Master key stored unencrypted on disk (like SSH keys - use full disk encryption)
- Shared key model (can't revoke individual users without rekeying)
- No key rotation without re-encrypting entire repo
- No per-user audit trail

These are design choices, not bugs. GitFoil prioritizes simplicity and automatic operation over fine-grained access control.

---

## Architecture (For People Who Care About This)

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

Translation: Use it. Break it. Fork it. Add more layers if you want (but why?! What is wrong with you?!) Just don't blame us if things go wrong, and don't claim we endorsed your seven-layer fork.

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

## Philosophical Note

Is six layers of encryption excessive? Yes.

Is it unnecessary for 99.9% of use cases? Probably.

Did it start as two and escalate? Absolutely.

But here's the thing: **great security should be invisible**. You set it up once, and then you forget it exists. Your files are encrypted in Git. Your team can collaborate normally. GitHub sees only ciphertext. Your working directory stays readable.

And if quantum computers ever do break modern encryption, or if some NSA slide deck leaks showing AES was compromised in 2019, or if your intern accidentally pushes the repo to a public GitLab...

You'll sleep soundly.

Because you have six layers of cascading cryptographic fury protecting your `database.env` file.

Is that rational? Debatable.

Is it effective? Absolutely.

Does it work? **Yes.**

And honestly? That's what matters.

---

## Set it up once. Then forget it exists.
*Six layers. Zero extra steps. Paranoia minimised.*
*Your files stay readable. Your repo stays encrypted. You can finally sleep at night.*
