# GitFoil v0.9: Architecture & Implementation Plan

**Status:** Planning
**Target Release:** Q4 2025
**Primary Goals:** Fix NIF loading, achieve <20ms/file performance, future-proof for key rotation

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current State & Problems](#current-state--problems)
3. [Architecture Decision: Mix Release + Git Process Filter](#architecture-decision-mix-release--git-process-filter)
4. [Technical Design](#technical-design)
5. [Implementation Phases](#implementation-phases)
6. [Testing Strategy](#testing-strategy)
7. [Distribution & Packaging](#distribution--packaging)
8. [Migration Path](#migration-path)
9. [Performance Targets](#performance-targets)
10. [Future Roadmap (v1.0+)](#future-roadmap-v10)
11. [Appendices](#appendices)

---

## Executive Summary

### The Problem

GitFoil v0.8 uses an escript-based architecture that fundamentally cannot load Native Implemented Functions (NIFs). This breaks all encryption/decryption operations because our Rust-based crypto libraries (AEGIS, Ascon, Schwaemm, Deoxys, ChaCha20) require native `.so` files that escripts cannot bundle or load.

### The Solution

**Replace escript with Mix Release + Git's built-in long-running process filter protocol.**

This architectural change delivers:
- ✅ **NIFs work:** Release bundles native libraries properly
- ✅ **100x faster:** Long-running BEAM process eliminates VM startup overhead
- ✅ **Simpler:** Git manages lifecycle, no custom daemon/socket/client code
- ✅ **Cross-platform:** Git's process filter protocol handles Windows/macOS/Linux
- ✅ **Future-proof:** Header format supports key rotation without breaking old commits

### Key Metrics

| Metric | Current (v0.8) | Target (v0.9) |
|--------|----------------|---------------|
| Startup time | N/A (broken) | <200ms |
| Per-file time (cold) | N/A (broken) | <200ms |
| Per-file time (warm) | N/A (broken) | **<20ms** |
| 3000 files `git add` | N/A (broken) | **<60 seconds** |
| Memory overhead | N/A | <50MB |

---

## Current State & Problems

### v0.8 Architecture (Broken)

```
┌─────────────────┐
│   git add       │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────┐
│  git-foil clean %f  (escript)   │
│  ┌──────────────────────────┐   │
│  │ Try to load NIFs         │   │
│  │ → FAILS: escripts can't  │   │
│  │   load .so files         │   │
│  └──────────────────────────┘   │
└─────────────────────────────────┘
         │
         ▼
    💥 ERROR 💥
```

**Problems:**
1. **Fatal:** Escripts fundamentally cannot load NIFs (native `.so` files)
2. **Performance:** Even if NIFs worked, spawning a new VM per file is ~1-2 seconds per file
3. **User Experience:** Ugly stack traces dumped to stderr
4. **Distribution:** Escripts are convenient but incompatible with our needs

### Why We Can't Just Fix the Escript

Escripts are ZIP archives containing:
- BEAM bytecode (compiled Elixir/Erlang)
- Application metadata
- **NO mechanism for native libraries**

The BEAM VM's `:code.priv_dir/1` function expects a specific directory structure that escripts don't provide. While workarounds exist (extract to temp directory, etc.), they're fragile and don't solve the performance problem.

---

## Architecture Decision: Mix Release + Git Process Filter

### Why Mix Release?

A Mix Release is an OTP release that bundles:
- ✅ Erlang Runtime System (ERTS)
- ✅ Application code (BEAM files)
- ✅ Dependencies
- ✅ **Native libraries (NIFs) in `priv/` directory**
- ✅ Boot scripts and configuration

This solves the NIF loading problem completely.

### Why Git Process Filter?

Git 2.11+ (released 2016) supports a **long-running filter protocol** via `filter.<driver>.process`:

**Traditional (per-file) filter:**
```
For each file:
  1. Spawn git-foil clean
  2. Boot BEAM VM (~1000ms)
  3. Load NIFs (~200ms)
  4. Encrypt file (~20ms)
  5. Shutdown VM (~50ms)
Total: ~1270ms per file
```

**Process filter (long-running):**
```
Once:
  1. Spawn git-foil filter --process
  2. Boot BEAM VM (~1000ms)
  3. Load NIFs (~200ms)

For each file (via stdin/stdout protocol):
  4. Encrypt file (~20ms)
  5. Encrypt next file (~20ms)
  6. Encrypt next file (~20ms)
  ...

Total: ~1200ms startup + ~20ms per file
For 1000 files: ~21 seconds vs ~21 minutes
```

**Benefits over custom daemon:**
- No need to write socket/IPC code
- No PID file management
- No daemon restart logic
- Git handles lifecycle, restarts, error recovery
- Cross-platform (Git abstracts Windows named pipes vs Unix sockets)
- Well-documented protocol

### Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| **Escript** | Single file, simple | Can't load NIFs | ❌ Rejected |
| **Mix run wrapper** | Simple | Requires source code, very slow | ❌ Rejected |
| **Bakeware/Burrito** | Single file with NIFs | Still spawns VM per call | ❌ Rejected |
| **Custom daemon + client** | Fast | Complex (sockets, lifecycle, etc.) | ❌ Rejected |
| **Mix Release + Git process filter** | Fast, simple, standard | Directory install vs single file | ✅ **Selected** |

---

## Technical Design

### System Architecture

```
┌───────────────────────────────────────────────────────────┐
│                      Git Repository                        │
└───────────────┬───────────────────────────────────────────┘
                │
                │ git add file.txt
                ▼
┌───────────────────────────────────────────────────────────┐
│                     Git Core                               │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  Reads: .gitattributes                              │  │
│  │  *.env filter=gitfoil                               │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                            │
│  Checks: git config filter.gitfoil.process                │
│         → /usr/local/lib/git_foil/bin/git-foil filter ... │
└───────────────┬───────────────────────────────────────────┘
                │
                │ Spawns once, keeps alive
                ▼
┌───────────────────────────────────────────────────────────┐
│          git-foil filter --process (BEAM VM)              │
│                                                            │
│  ┌──────────────────────────────────────────────────┐    │
│  │  Handshake: version=2, capability=clean/smudge   │    │
│  └──────────────────────────────────────────────────┘    │
│                                                            │
│  ┌──────────────────────────────────────────────────┐    │
│  │  Loop: Read pkt-line request                      │    │
│  │        → command=clean, pathname=file.txt         │    │
│  │        → Read blob from stdin                     │    │
│  │        → Encrypt (NIFs loaded, cached)            │    │
│  │        → Write blob to stdout                     │    │
│  │        → status=success                           │    │
│  │        → Repeat for next file...                  │    │
│  └──────────────────────────────────────────────────┘    │
│                                                            │
│  ┌──────────────────────────────────────────────────┐    │
│  │  NIF Modules (loaded once):                       │    │
│  │  - AEGIS-256       (Rust, libaegis_nif.so)       │    │
│  │  - Ascon-128a      (Rust, libascon_nif.so)       │    │
│  │  - Schwaemm-256    (Rust, libschwaemm_nif.so)    │    │
│  │  - Deoxys-II-256   (Rust, libdeoxys_nif.so)      │    │
│  │  - ChaCha20-Poly1305 (Rust, libchacha20...)      │    │
│  │  - OpenSSL AES-256-GCM (native)                  │    │
│  └──────────────────────────────────────────────────┘    │
└───────────────────────────────────────────────────────────┘
```

### Blob Format (HeaderV1)

Every encrypted blob starts with a header that enables:
- Algorithm identification
- Key rotation
- Version evolution
- Nonce storage

```
┌────────────────────────────────────────────────────────────┐
│                     Encrypted Blob                          │
├────────────────────────────────────────────────────────────┤
│  Header V1 (45 bytes)                                      │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  magic:      4 bytes  = "GFO1"                       │ │
│  │  kid:        8 bytes  = key identifier (hex)         │ │
│  │  alg:        1 byte   = algorithm enum               │ │
│  │  nonce:     32 bytes  = per-blob random              │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
│  Ciphertext (variable length)                              │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  Layer 6: ChaCha20-Poly1305 (outermost)             │ │
│  │    Layer 5: Ascon-128a                               │ │
│  │      Layer 4: Deoxys-II-256                          │ │
│  │        Layer 3: Schwaemm-256                         │ │
│  │          Layer 2: AEGIS-256                          │ │
│  │            Layer 1: AES-256-GCM (plaintext)          │ │
│  └──────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

**Header Details:**

| Field | Size | Format | Purpose |
|-------|------|--------|---------|
| `magic` | 4 bytes | ASCII "GFO1" | Format identification, fast rejection |
| `kid` | 8 bytes | Hex string | Key identifier (random CSPRNG, not hash) |
| `alg` | 1 byte | Enum | Algorithm: 0x01 = six-layer-v1 |
| `nonce` | 32 bytes | Binary | Per-blob random nonce for deterministic derivation |

**Why 8-byte KID:**
- 4 bytes: 4.3 billion possible keys (collision risk in large repos)
- 8 bytes: 18 quintillion keys (no practical collision risk)
- 16 bytes: Overkill, wastes space
- Decision: 8 bytes (64-bit hex string like "e8d2b1f4a3c9d7e2")

**Algorithm Enum Values:**
```
0x00 = reserved
0x01 = six-layer-v1 (current: AES + AEGIS + Schwaemm + Deoxys + Ascon + ChaCha20)
0x02-0xFF = future algorithms
```

This allows algorithm evolution without format changes.

### Key Store Format

**Location:** `.git/git_foil/keys.json` (never committed)

```json
{
  "version": 1,
  "active_kid": "e8d2b1f4a3c9d7e2",
  "keys": {
    "e8d2b1f4a3c9d7e2": {
      "alg": "six-layer-v1",
      "created_at": "2025-10-14T22:00:00Z",
      "keypair": {
        "kyber_public": "<base64>",
        "kyber_secret": "<base64>",
        "classical_key": "<base64>"
      }
    },
    "5a9c7e02f1b8": {
      "alg": "six-layer-v1",
      "created_at": "2025-05-10T15:30:00Z",
      "keypair": {
        "kyber_public": "<base64>",
        "kyber_secret": "<base64>",
        "classical_key": "<base64>"
      }
    }
  }
}
```

**Fields:**
- `version`: Format version (1 for v0.9)
- `active_kid`: Which key to use for **new encryptions**
- `keys`: Map of KID → key material

**Key Properties:**
- Multiple keys can coexist (enables rotation)
- Old keys remain for decryption
- New files always use `active_kid`
- Key deletion breaks history (dangerous, requires explicit confirmation)

**Security Properties:**
- File permissions: 0600 (owner read/write only)
- Never committed to Git (in `.gitignore`)
- Backed up via `git-foil key export` (encrypted with password)
- Restored via `git-foil key import`

### Git Process Filter Protocol

Git's pkt-line protocol for long-running filters:

**1. Handshake (on startup):**
```
git-foil → stdout:
  0023version=2\n
  0018capability=clean\n
  0019capability=smudge\n
  0000  # flush packet
```

**2. Request (for each file):**
```
git → stdin:
  001dcommand=clean\n
  001fpathname=secrets.env\n
  000dcan-delay=1\n
  0000  # flush packet
  <size bytes of file content>
  0000  # flush packet
```

**3. Response (from git-foil):**
```
git-foil → stdout:
  <size bytes of encrypted content>
  0000  # flush packet
  0011status=success\n
  0000  # flush packet
```

**4. Error Response:**
```
git-foil → stdout:
  0011status=error\n
  0034error: Crypto library not loaded\n
  0000  # flush packet
```

**Pkt-line format:**
- 4 hex digits = payload length (includes 4-byte length itself)
- "0000" = flush packet (delimiter)
- "0001" = delim packet (separator)
- "0002" = response end packet

**Implementation notes:**
- Read from stdin, write to stdout (binary mode)
- **Never write to stdout except protocol responses** (use stderr for logs/debug)
- Handle multiple concurrent requests (Git can pipeline)
- Graceful shutdown on stdin close

### Module Architecture

```
lib/git_foil/
├── application.ex                 # OTP application
├── cli.ex                         # Entry point (mix release executable)
│
├── filter/
│   ├── process_protocol.ex       # Git process filter implementation
│   ├── pkt_line.ex               # Pkt-line encoding/decoding
│   └── legacy.ex                 # Fallback clean/smudge for Git < 2.11
│
├── crypto/
│   ├── engine.ex                 # Six-layer encryption coordinator
│   ├── header.ex                 # HeaderV1 encode/decode/validate
│   └── nif_warmer.ex             # Touch each NIF at startup
│
├── key_manager/
│   ├── store.ex                  # keys.json CRUD operations
│   ├── generator.ex              # Key generation (KID assignment)
│   ├── exporter.ex               # Export keys (encrypted with password)
│   └── importer.ex               # Import keys (decrypt, validate)
│
├── commands/
│   ├── init.ex                   # Initialize GitFoil in repo
│   ├── audit.ex                  # Scan repo for KIDs in use
│   ├── encrypt.ex                # Baseline encrypt (initial setup)
│   └── unencrypt.ex              # Remove encryption (unchanged)
│
└── infrastructure/
    ├── git.ex                    # Git command wrappers
    └── terminal.ex               # UI helpers (progress, spinners)
```

---

## Implementation Phases

### Phase 1: Format & Protocol Foundation (Week 1)

**Goals:**
- Define blob format (HeaderV1)
- Implement pkt-line protocol
- Update key store to use KIDs

**Tasks:**

#### 1.1: Header V1 Module
```elixir
defmodule GitFoil.Crypto.Header do
  @moduledoc """
  Encodes and decodes GitFoil blob headers (version 1).

  Format:
    magic:  4 bytes = "GFO1"
    kid:    8 bytes = hex string
    alg:    1 byte  = algorithm enum
    nonce: 32 bytes = random
  """

  @type t :: %__MODULE__{
    magic: binary(),
    kid: String.t(),
    alg: non_neg_integer(),
    nonce: binary()
  }

  defstruct [:magic, :kid, :alg, :nonce]

  @magic "GFO1"
  @header_size 45
  @alg_six_layer_v1 0x01

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = header)

  @spec decode(binary()) :: {:ok, t(), rest :: binary()} | {:error, term()}
  def decode(data)

  @spec new(kid :: String.t()) :: t()
  def new(kid)

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = header)
end
```

**Tests:**
- Round-trip encode/decode
- Invalid magic rejection
- Invalid KID rejection (not 8 bytes hex)
- Nonce randomness (statistical test)

#### 1.2: Pkt-line Module
```elixir
defmodule GitFoil.Filter.PktLine do
  @moduledoc """
  Git pkt-line protocol encoder/decoder.

  Format:
    4 hex digits = length (includes length itself)
    "0000" = flush packet
    "0001" = delim packet
    "0002" = response end packet
  """

  @type packet :: binary() | :flush | :delim | :response_end

  @spec read(IO.device()) :: {:ok, packet()} | {:error, term()} | :eof
  def read(device \\ :stdio)

  @spec write(IO.device(), packet()) :: :ok
  def write(device \\ :stdio, packet)

  @spec read_request(IO.device()) :: {:ok, request()} | {:error, term()}
  def read_request(device \\ :stdio)

  @spec write_response(IO.device(), status :: :success | :error, binary()) :: :ok
  def write_response(device \\ :stdio, status, data \\ "")

  @spec write_blob(IO.device(), binary()) :: :ok
  def write_blob(device \\ :stdio, data)
end
```

**Tests:**
- Encode/decode all packet types
- Handle truncated input (malformed length)
- Binary data handling (non-UTF8)
- Large blobs (streaming)

#### 1.3: Process Protocol Module
```elixir
defmodule GitFoil.Filter.ProcessProtocol do
  @moduledoc """
  Implements Git's long-running filter protocol.

  Lifecycle:
  1. Handshake: advertise capabilities
  2. Loop: read request → process → write response
  3. Shutdown: stdin closes
  """

  use GenServer
  require Logger

  def start_link(opts \\ [])

  def run do
    # Entry point for `git-foil filter --process`
    handshake()
    loop()
  end

  defp handshake
  defp loop
  defp handle_request(command, headers, data)
end
```

**Tasks:**
- Handshake implementation
- Request loop with error handling
- Clean/smudge dispatch
- Graceful shutdown on stdin close

#### 1.4: Key Store with KIDs
```elixir
defmodule GitFoil.KeyManager.Store do
  @moduledoc """
  Manages keys.json with support for multiple keys (KIDs).
  """

  @type kid :: String.t()  # 8-byte hex string
  @type key_entry :: %{
    alg: String.t(),
    created_at: DateTime.t(),
    keypair: map()
  }
  @type store :: %{
    version: pos_integer(),
    active_kid: kid(),
    keys: %{kid() => key_entry()}
  }

  @spec load() :: {:ok, store()} | {:error, term()}
  def load

  @spec save(store()) :: :ok | {:error, term()}
  def save(store)

  @spec get_active_key() :: {:ok, kid(), key_entry()} | {:error, :not_found}
  def get_active_key

  @spec get_key(kid()) :: {:ok, key_entry()} | {:error, :not_found}
  def get_key(kid)

  @spec add_key(kid(), key_entry()) :: :ok | {:error, term()}
  def add_key(kid, entry)

  @spec set_active(kid()) :: :ok | {:error, :not_found}
  def set_active(kid)
end
```

**Migration:**
- Convert existing `master.key` to keys.json format
- Generate random KID for existing key
- Preserve backward compatibility (read old format, write new)

**Deliverables:**
- ✅ `GitFoil.Crypto.Header` with tests
- ✅ `GitFoil.Filter.PktLine` with tests
- ✅ `GitFoil.Filter.ProcessProtocol` skeleton
- ✅ `GitFoil.KeyManager.Store` with KID support
- ✅ Migration script for existing keys

---

### Phase 2: Mix Release & NIF Infrastructure (Week 2)

**Goals:**
- Configure Mix Release properly
- Add `rustler_precompiled` for NIF distribution
- Set up CI for NIF builds
- Test release on macOS/Linux

**Tasks:**

#### 2.1: Mix Release Configuration

**Update `mix.exs`:**
```elixir
defmodule GitFoil.MixProject do
  use Mix.Project

  def project do
    [
      app: :git_foil,
      version: "0.9.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      rustler_crates: rustler_crates()
    ]
  end

  defp releases do
    [
      git_foil: [
        include_executables_for: [:unix],
        applications: [
          git_foil: :permanent,
          runtime_tools: :permanent
        ],
        steps: [:assemble, &copy_priv_native/1],
        strip_beams: false,  # Keep for debugging, NIFs need full beams
        cookie: "git_foil_release_cookie"
      ]
    ]
  end

  defp copy_priv_native(release) do
    # Ensure NIFs are in the right location
    priv_native = Path.join([release.path, "lib", "git_foil-#{release.version}", "priv", "native"])
    File.mkdir_p!(priv_native)

    # Copy all .so files
    Path.wildcard("priv/native/*.so")
    |> Enum.each(fn so_file ->
      dest = Path.join(priv_native, Path.basename(so_file))
      File.cp!(so_file, dest)
    end)

    release
  end

  defp rustler_crates do
    mode = if Mix.env() == :prod, do: :release, else: :debug

    [
      ascon_nif: [path: "native/ascon_nif", mode: mode],
      aegis_nif: [path: "native/aegis_nif", mode: mode],
      schwaemm_nif: [path: "native/schwaemm_nif", mode: mode],
      deoxys_nif: [path: "native/deoxys_nif", mode: mode],
      chacha20poly1305_nif: [path: "native/chacha20poly1305_nif", mode: mode]
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:pqclean, "~> 0.0.3"},
      {:rustler, "~> 0.34.0"},
      {:rustler_precompiled, "~> 0.8"},

      # ... rest of deps
    ]
  end
end
```

**Create `rel/env.sh.eex`:**
```bash
#!/bin/sh

# Optimize BEAM for crypto workload
export ERL_FLAGS="-noshell -noinput +sbwt none +sbwtdcpu none +sbwtdio none +sssdio 0"

# Debugging (optional)
if [ -n "$GIT_FOIL_DEBUG" ]; then
  export ERL_FLAGS="$ERL_FLAGS +pc unicode -kernel logger_level debug"
fi
```

#### 2.2: Rustler Precompiled Setup

**Goal:** Ship prebuilt NIFs so users don't need Rust toolchain.

**Add to each NIF crate's `mix.exs`:**
```elixir
def project do
  [
    # ... existing config
    rustler_precompiled: rustler_precompiled()
  ]
end

defp rustler_precompiled do
  [
    # Available precompiled artifacts
    available_targets: [
      "aarch64-apple-darwin",
      "x86_64-apple-darwin",
      "x86_64-unknown-linux-gnu",
      "aarch64-unknown-linux-gnu"
    ],
    # Where to fetch from
    base_url: "https://github.com/code-of-kai/git-foil/releases/download/v#{@version}",
    # Fallback to compilation if precompiled not available
    force_build?: System.get_env("RUSTLER_PRECOMPILED_FORCE_BUILD") in ["1", "true"]
  ]
end
```

**Update `.github/workflows/build_nifs.yml`:**
```yaml
name: Build and Release NIFs

on:
  release:
    types: [published]

jobs:
  build-nifs:
    strategy:
      matrix:
        include:
          - target: aarch64-apple-darwin
            os: macos-14  # M1
          - target: x86_64-apple-darwin
            os: macos-13  # Intel
          - target: x86_64-unknown-linux-gnu
            os: ubuntu-latest
          - target: aarch64-unknown-linux-gnu
            os: ubuntu-latest

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          otp-version: '28'
          elixir-version: '1.18'

      - name: Install Rust
        uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
          target: ${{ matrix.target }}

      - name: Build NIFs
        run: |
          mix deps.get
          mix compile

      - name: Package NIFs
        run: |
          mkdir -p artifacts
          tar -czf artifacts/nifs-${{ matrix.target }}.tar.gz priv/native/*.so

      - name: Upload to Release
        uses: actions/upload-release-asset@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          upload_url: ${{ github.event.release.upload_url }}
          asset_path: artifacts/nifs-${{ matrix.target }}.tar.gz
          asset_name: nifs-${{ matrix.target }}.tar.gz
          asset_content_type: application/gzip
```

#### 2.3: NIF Warming at Startup

**Purpose:** Load NIFs once at process start to avoid lazy-loading latency.

```elixir
defmodule GitFoil.Crypto.NifWarmer do
  @moduledoc """
  Warms up all NIF modules by calling a lightweight function in each.
  This ensures NIFs are loaded before the first encrypt/decrypt request.
  """

  require Logger

  @nif_modules [
    GitFoil.Native.AegisNif,
    GitFoil.Native.AsconNif,
    GitFoil.Native.SchwaemmNif,
    GitFoil.Native.DeoxysNif,
    GitFoil.Native.ChaCha20Poly1305Nif
  ]

  def warm_all do
    Logger.debug("Warming NIF modules...")
    start_time = System.monotonic_time(:millisecond)

    Enum.each(@nif_modules, fn mod ->
      try do
        # Call a lightweight test function (e.g., version check)
        case mod.loaded?() do
          :ok -> :ok
          {:error, reason} ->
            Logger.error("Failed to load NIF #{inspect(mod)}: #{inspect(reason)}")
            raise "NIF loading failed: #{mod}"
        end
      rescue
        e ->
          Logger.error("Exception warming #{inspect(mod)}: #{inspect(e)}")
          reraise e, __STACKTRACE__
      end
    end)

    elapsed = System.monotonic_time(:millisecond) - start_time
    Logger.info("All NIFs loaded in #{elapsed}ms")
    :ok
  end
end
```

**Add to Application startup:**
```elixir
defmodule GitFoil.Application do
  use Application

  def start(_type, _args) do
    # Warm NIFs before accepting requests
    GitFoil.Crypto.NifWarmer.warm_all()

    children = [
      {Task.Supervisor, name: GitFoil.Filter.TaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: GitFoil.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

#### 2.4: Testing Release

**Build and test:**
```bash
# Clean build
rm -rf _build/prod
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix compile

# Build release
MIX_ENV=prod mix release

# Test executable
_build/prod/rel/git_foil/bin/git-foil --version
_build/prod/rel/git_foil/bin/git-foil filter --process < /dev/null

# Check NIF locations
find _build/prod/rel/git_foil -name "*.so"

# Test filter protocol (manual)
echo -e "0023version=2\n0018capability=clean\n0000" | \
  _build/prod/rel/git_foil/bin/git-foil filter --process
```

**Deliverables:**
- ✅ Mix release configuration
- ✅ Rustler precompiled setup
- ✅ CI workflow for NIF builds
- ✅ NIF warming module
- ✅ Release builds successfully on macOS/Linux
- ✅ NIFs load correctly in release

---

### Phase 3: Commands & User Experience (Week 3)

**Goals:**
- Implement `git-foil filter --process` command
- Update `git-foil init` for new Git config
- Implement key management commands
- Implement `git-foil audit`

**Tasks:**

#### 3.1: CLI Entry Point

**Update `lib/git_foil/cli.ex`:**
```elixir
defmodule GitFoil.CLI do
  @moduledoc """
  Command-line interface for GitFoil.
  """

  def main(args) do
    result = run(args)
    handle_result(result)
  end

  def run(args) do
    parse_args(args)
    |> execute()
  end

  defp parse_args([]), do: {:help, []}
  defp parse_args(["--version"]), do: {:version, []}
  defp parse_args(["help" | _]), do: {:help, []}

  # Primary: process filter mode
  defp parse_args(["filter", "--process" | rest]), do: {:filter_process, parse_options(rest)}

  # Fallback: legacy clean/smudge
  defp parse_args(["clean", file_path | rest]) when is_binary(file_path) do
    {:clean, [file_path: file_path] ++ parse_options(rest)}
  end
  defp parse_args(["smudge", file_path | rest]) when is_binary(file_path) do
    {:smudge, [file_path: file_path] ++ parse_options(rest)}
  end

  # Key management
  defp parse_args(["key", "generate" | rest]), do: {:key_generate, parse_options(rest)}
  defp parse_args(["key", "activate", kid | rest]), do: {:key_activate, [kid: kid] ++ parse_options(rest)}
  defp parse_args(["key", "list" | rest]), do: {:key_list, parse_options(rest)}
  defp parse_args(["key", "export" | rest]), do: {:key_export, parse_options(rest)}
  defp parse_args(["key", "import" | rest]), do: {:key_import, parse_options(rest)}

  # Repository commands
  defp parse_args(["init" | rest]), do: {:init, parse_options(rest)}
  defp parse_args(["audit" | rest]), do: {:audit, parse_options(rest)}

  # ... rest of existing commands

  defp execute({:filter_process, _opts}) do
    GitFoil.Filter.ProcessProtocol.run()
  end

  defp execute({:key_generate, opts}) do
    GitFoil.Commands.Key.generate(opts)
  end

  # ... rest of execute implementations
end
```

#### 3.2: Updated Init Command

**Update `git-foil init` to configure process filter:**
```elixir
defmodule GitFoil.Commands.Init do
  def run(opts \\ []) do
    force = Keyword.get(opts, :force, false)

    with :ok <- verify_git_repository(),
         :ok <- check_already_initialized(force),
         {:ok, executable_path} <- get_executable_path(),
         {:ok, kid} <- generate_or_load_key(force),
         :ok <- configure_git_filters(executable_path),
         :ok <- maybe_configure_patterns(opts),
         {:ok, encrypted} <- maybe_baseline_encrypt(opts) do
      {:ok, success_message(kid, encrypted)}
    end
  end

  defp configure_git_filters(executable_path) do
    # Primary: process filter (Git >= 2.11)
    filters = [
      {"filter.gitfoil.process", "#{executable_path} filter --process"},
      {"filter.gitfoil.required", "true"}
    ]

    # Fallback: per-file filters (Git < 2.11)
    fallback_filters = [
      {"filter.gitfoil.clean", "#{executable_path} clean %f"},
      {"filter.gitfoil.smudge", "#{executable_path} smudge %f"}
    ]

    all_filters = filters ++ fallback_filters

    Enum.each(all_filters, fn {key, value} ->
      case System.cmd("git", ["config", key, value], stderr_to_stdout: true) do
        {_, 0} -> :ok
        {error, _} ->
          IO.puts(:stderr, "Warning: Failed to set #{key}: #{error}")
          :ok  # Continue anyway
      end
    end)

    :ok
  end
end
```

#### 3.3: Key Management Commands

**Key Generation:**
```elixir
defmodule GitFoil.Commands.Key do
  alias GitFoil.KeyManager.{Store, Generator}

  def generate(opts) do
    alg = Keyword.get(opts, :alg, "six-layer-v1")
    kid = Keyword.get(opts, :kid) || Generator.generate_kid()

    IO.puts("🔑  Generating new encryption key...")
    IO.puts("   Algorithm: #{alg}")
    IO.puts("   Key ID: #{kid}")

    # Generate keypair
    {:ok, keypair} = Generator.generate_keypair()

    entry = %{
      alg: alg,
      created_at: DateTime.utc_now(),
      keypair: keypair
    }

    # Add to store
    {:ok, store} = Store.load()
    updated = %{store |
      keys: Map.put(store.keys, kid, entry),
      active_kid: kid  # New key becomes active
    }
    :ok = Store.save(updated)

    IO.puts("\n✅  Key generated successfully")
    IO.puts("   Active key is now: #{kid}")
    {:ok, ""}
  end

  def activate(opts) do
    kid = Keyword.fetch!(opts, :kid)

    {:ok, store} = Store.load()

    unless Map.has_key?(store.keys, kid) do
      {:error, "Key #{kid} not found. Run 'git-foil key list' to see available keys."}
    else
      updated = %{store | active_kid: kid}
      :ok = Store.save(updated)

      {:ok, "✅  Active key changed to #{kid}"}
    end
  end

  def list(_opts) do
    {:ok, store} = Store.load()

    IO.puts("🔑  Keys in keystore:")
    IO.puts("")

    Enum.each(store.keys, fn {kid, entry} ->
      active = if kid == store.active_kid, do: " (active)", else: ""
      IO.puts("   #{kid}#{active}")
      IO.puts("      Algorithm: #{entry.alg}")
      IO.puts("      Created: #{DateTime.to_string(entry.created_at)}")
      IO.puts("")
    end)

    {:ok, ""}
  end

  def export(opts) do
    output_file = Keyword.get(opts, :output, "gitfoil-keys.backup")

    # Get password
    password = IO.gets("Enter password to encrypt backup: ") |> String.trim()
    password_confirm = IO.gets("Confirm password: ") |> String.trim()

    if password != password_confirm do
      {:error, "Passwords do not match"}
    else
      {:ok, store} = Store.load()

      # Encrypt store with password
      encrypted = GitFoil.Crypto.PasswordProtection.encrypt(
        :erlang.term_to_binary(store),
        password
      )

      File.write!(output_file, encrypted)
      {:ok, "✅  Keys exported to #{output_file}"}
    end
  end

  def import(opts) do
    input_file = Keyword.get(opts, :input, "gitfoil-keys.backup")

    unless File.exists?(input_file) do
      {:error, "File not found: #{input_file}"}
    else
      password = IO.gets("Enter password to decrypt backup: ") |> String.trim()

      encrypted = File.read!(input_file)

      case GitFoil.Crypto.PasswordProtection.decrypt(encrypted, password) do
        {:ok, decrypted} ->
          store = :erlang.binary_to_term(decrypted)
          :ok = Store.save(store)
          {:ok, "✅  Keys imported successfully"}

        {:error, :invalid_password} ->
          {:error, "Invalid password"}
      end
    end
  end
end
```

#### 3.4: Audit Command

**Scan repository for KID usage:**
```elixir
defmodule GitFoil.Commands.Audit do
  alias GitFoil.Crypto.Header

  def run(_opts) do
    IO.puts("🔍  Auditing repository for encrypted files...")

    # Get all tracked files with gitfoil filter
    {:ok, files} = get_encrypted_files()

    # Group by KID
    kid_map = Enum.reduce(files, %{}, fn file, acc ->
      case get_kid_for_file(file) do
        {:ok, kid} ->
          Map.update(acc, kid, [file], &[file | &1])

        {:error, _reason} ->
          Map.update(acc, :error, [file], &[file | &1])
      end
    end)

    # Display results
    IO.puts("")
    IO.puts("📊  Encryption key usage:")
    IO.puts("")

    Enum.each(kid_map, fn
      {:error, files} ->
        IO.puts("   ❌  Unreadable (#{length(files)} files):")
        Enum.each(Enum.take(files, 5), &IO.puts("      - #{&1}"))
        if length(files) > 5, do: IO.puts("      ... and #{length(files) - 5} more")

      {kid, files} ->
        IO.puts("   🔑  #{kid} (#{length(files)} files):")
        Enum.each(Enum.take(files, 5), &IO.puts("      - #{&1}"))
        if length(files) > 5, do: IO.puts("      ... and #{length(files) - 5} more")
    end)

    {:ok, ""}
  end

  defp get_encrypted_files do
    {output, 0} = System.cmd("git", ["ls-files"], stderr_to_stdout: true)

    files = output
    |> String.split("\n", trim: true)
    |> Enum.filter(fn file ->
      {attr_output, 0} = System.cmd("git", ["check-attr", "filter", file])
      String.contains?(attr_output, "filter: gitfoil")
    end)

    {:ok, files}
  end

  defp get_kid_for_file(file) do
    # Read from Git's object database (not working tree)
    case System.cmd("git", ["show", "HEAD:#{file}"], stderr_to_stdout: true) do
      {blob, 0} ->
        case Header.decode(blob) do
          {:ok, %Header{kid: kid}, _rest} -> {:ok, kid}
          {:error, reason} -> {:error, reason}
        end

      {_error, _} ->
        {:error, :not_in_git}
    end
  end
end
```

**Deliverables:**
- ✅ `git-foil filter --process` command
- ✅ Updated `git-foil init` with process filter config
- ✅ Key management commands (generate, activate, list, export, import)
- ✅ `git-foil audit` command
- ✅ Help text and error messages
- ✅ Man page / documentation

---

### Phase 4: Testing & Performance Validation (Week 4)

**Goals:**
- Comprehensive testing
- Performance benchmarks
- Documentation
- Homebrew formula

**Tasks:**

#### 4.1: Integration Tests

**Test Suite Structure:**
```
test/
├── integration/
│   ├── process_filter_test.exs       # End-to-end process filter
│   ├── legacy_filter_test.exs        # Fallback clean/smudge
│   ├── key_rotation_test.exs         # Multi-key scenarios
│   └── performance_test.exs          # Benchmark suite
├── git_foil/
│   ├── crypto/
│   │   ├── header_test.exs           # HeaderV1 encode/decode
│   │   └── engine_test.exs           # Six-layer encryption
│   ├── filter/
│   │   ├── pkt_line_test.exs         # Protocol encoding
│   │   └── process_protocol_test.exs # Request handling
│   └── key_manager/
│       └── store_test.exs            # Key store operations
```

**Critical Test Cases:**

**1. Process Filter Round-trip:**
```elixir
defmodule GitFoil.Integration.ProcessFilterTest do
  use ExUnit.Case

  test "encrypts and decrypts files via process filter" do
    # Start process filter
    {:ok, filter_pid} = start_filter_process()

    # Send clean request
    plaintext = "secret data"
    encrypted = send_clean_request(filter_pid, "test.txt", plaintext)

    assert encrypted != plaintext
    assert byte_size(encrypted) > byte_size(plaintext)

    # Send smudge request
    decrypted = send_smudge_request(filter_pid, "test.txt", encrypted)

    assert decrypted == plaintext
  end

  test "handles 1000 files without leaking memory" do
    {:ok, filter_pid} = start_filter_process()

    initial_memory = get_process_memory(filter_pid)

    for i <- 1..1000 do
      plaintext = "file #{i} content"
      encrypted = send_clean_request(filter_pid, "file#{i}.txt", plaintext)
      decrypted = send_smudge_request(filter_pid, "file#{i}.txt", encrypted)
      assert decrypted == plaintext
    end

    final_memory = get_process_memory(filter_pid)

    # Memory should not grow more than 10MB
    assert final_memory - initial_memory < 10_000_000
  end
end
```

**2. Key Rotation:**
```elixir
defmodule GitFoil.Integration.KeyRotationTest do
  use ExUnit.Case

  test "decrypts files encrypted with old key after rotation" do
    # Generate initial key
    {:ok, kid1} = GitFoil.Commands.Key.generate([])

    # Encrypt file
    plaintext = "original data"
    {:ok, encrypted1} = encrypt_with_kid(plaintext, kid1)

    # Generate new key and activate
    {:ok, kid2} = GitFoil.Commands.Key.generate([])
    :ok = GitFoil.Commands.Key.activate(kid: kid2)

    # Encrypt new file
    {:ok, encrypted2} = encrypt_with_kid(plaintext, kid2)

    # Verify both can be decrypted
    {:ok, decrypted1} = decrypt(encrypted1)
    {:ok, decrypted2} = decrypt(encrypted2)

    assert decrypted1 == plaintext
    assert decrypted2 == plaintext
  end
end
```

**3. Malformed Input Handling:**
```elixir
test "rejects invalid headers gracefully" do
  invalid_headers = [
    "INVALID_MAGIC" <> random_bytes(41),
    "GFO1" <> "not_hex!" <> random_bytes(33),
    "GFO1" <> valid_kid() <> <<0xFF>> <> random_bytes(32),  # Invalid alg
    random_bytes(45)  # Completely random
  ]

  Enum.each(invalid_headers, fn invalid ->
    assert {:error, _reason} = GitFoil.Crypto.Header.decode(invalid)
  end)
end
```

#### 4.2: Performance Benchmarks

**Benchmark Suite:**
```elixir
defmodule GitFoil.Integration.PerformanceTest do
  use ExUnit.Case

  @tag :benchmark
  test "baseline: cold start time" do
    {time_us, _} = :timer.tc(fn ->
      # Start process, warm NIFs, shutdown
      {:ok, pid} = start_filter_process()
      Process.exit(pid, :normal)
    end)

    time_ms = time_us / 1000
    IO.puts("\n⏱️  Cold start: #{time_ms}ms")

    assert time_ms < 200, "Cold start exceeded 200ms: #{time_ms}ms"
  end

  @tag :benchmark
  test "per-file latency (warm)" do
    {:ok, pid} = start_filter_process()

    # Warm up
    for _ <- 1..10 do
      send_clean_request(pid, "warmup.txt", "warmup data")
    end

    # Measure
    latencies = for i <- 1..100 do
      plaintext = "test data #{i}"
      {time_us, _encrypted} = :timer.tc(fn ->
        send_clean_request(pid, "test#{i}.txt", plaintext)
      end)
      time_us / 1000  # Convert to ms
    end

    avg = Enum.sum(latencies) / length(latencies)
    p50 = percentile(latencies, 50)
    p95 = percentile(latencies, 95)
    p99 = percentile(latencies, 99)

    IO.puts("\n⏱️  Per-file latency (warm):")
    IO.puts("   Average: #{Float.round(avg, 2)}ms")
    IO.puts("   p50: #{Float.round(p50, 2)}ms")
    IO.puts("   p95: #{Float.round(p95, 2)}ms")
    IO.puts("   p99: #{Float.round(p99, 2)}ms")

    assert p95 < 20, "p95 latency exceeded 20ms: #{p95}ms"
  end

  @tag :benchmark
  test "throughput: 3000 files" do
    {:ok, pid} = start_filter_process()

    files = for i <- 1..3000 do
      {"file#{i}.txt", "content for file #{i}"}
    end

    {time_us, _results} = :timer.tc(fn ->
      Enum.map(files, fn {path, content} ->
        encrypted = send_clean_request(pid, path, content)
        send_smudge_request(pid, path, encrypted)
      end)
    end)

    time_sec = time_us / 1_000_000
    throughput = 3000 / time_sec

    IO.puts("\n⏱️  Throughput (3000 files):")
    IO.puts("   Total time: #{Float.round(time_sec, 2)}s")
    IO.puts("   Files/sec: #{Float.round(throughput, 2)}")

    assert time_sec < 60, "3000 files took longer than 60s: #{time_sec}s"
  end
end
```

**Run benchmarks:**
```bash
mix test --only benchmark --trace
```

#### 4.3: Documentation

**User Documentation:**
- README updates
- Installation guide
- Quick start guide
- Migration from v0.8
- Troubleshooting guide
- Performance tuning tips

**Developer Documentation:**
- Architecture overview
- Protocol specification
- Testing guide
- Contributing guide

**Man Pages:**
```bash
# Generate man pages
scripts/generate_man_pages.sh

# Installs to /usr/local/share/man/man1/
man git-foil
man git-foil-init
man git-foil-key
```

#### 4.4: Homebrew Formula

**Create `Formula/git-foil.rb`:**
```ruby
class GitFoil < Formula
  desc "Quantum-resistant Git encryption with six layers of security"
  homepage "https://github.com/code-of-kai/git-foil"
  url "https://github.com/code-of-kai/git-foil/releases/download/v0.9.0/git-foil-0.9.0-macos.tar.gz"
  sha256 "..."
  license "MIT"

  depends_on "erlang" => :runtime

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"bin/git-foil"
    man1.install Dir[libexec/"share/man/man1/*.1"]
  end

  test do
    system bin/"git-foil", "--version"
    assert_match "GitFoil version 0.9.0", shell_output("#{bin}/git-foil --version")
  end
end
```

**Testing:**
```bash
# Local test
brew install --build-from-source Formula/git-foil.rb

# Verify
git-foil --version
which git-foil
man git-foil
```

**Deliverables:**
- ✅ Comprehensive test suite (unit + integration)
- ✅ Performance benchmarks with results
- ✅ User documentation (README, guides)
- ✅ Developer documentation
- ✅ Man pages
- ✅ Homebrew formula
- ✅ Release checklist

---

## Testing Strategy

### Test Pyramid

```
          ┌──────────────┐
          │  End-to-End  │  (5% - slow, high value)
          │   git add    │
          └──────────────┘
        ┌────────────────────┐
        │   Integration      │  (20% - medium speed)
        │  Process filter    │
        │  Key rotation      │
        └────────────────────┘
    ┌──────────────────────────────┐
    │      Unit Tests              │  (75% - fast)
    │  Header, PktLine, Crypto     │
    └──────────────────────────────┘
```

### Test Categories

**1. Unit Tests (Fast, Isolated)**
- Crypto: Each layer individually
- Header: Encode/decode/validate
- PktLine: Protocol encoding
- KeyStore: CRUD operations
- ~500 tests, <10 seconds total

**2. Integration Tests (Medium, With Dependencies)**
- Process filter: Full request/response cycle
- Legacy filter: Backward compatibility
- Key rotation: Multi-key scenarios
- Error handling: Malformed input
- ~100 tests, <60 seconds total

**3. End-to-End Tests (Slow, Real Git)**
- `git add` with process filter
- `git checkout` (smudge)
- Multiple file operations
- Repository migration
- ~20 tests, <5 minutes total

**4. Performance Tests (Benchmarks)**
- Cold start time
- Warm per-file latency
- Throughput (3000 files)
- Memory usage
- ~10 tests, <10 minutes total

### CI Pipeline

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-14]
        elixir: ['1.18']
        otp: ['28']

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          otp-version: ${{ matrix.otp }}
          elixir-version: ${{ matrix.elixir }}

      - name: Cache deps
        uses: actions/cache@v3
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}

      - name: Install dependencies
        run: mix deps.get

      - name: Compile NIFs
        run: mix compile

      - name: Run unit tests
        run: mix test --exclude integration --exclude benchmark

      - name: Run integration tests
        run: mix test --only integration

      - name: Run benchmarks (on main only)
        if: github.ref == 'refs/heads/main'
        run: mix test --only benchmark

      - name: Build release
        run: MIX_ENV=prod mix release

      - name: Test release
        run: |
          _build/prod/rel/git_foil/bin/git-foil --version
          _build/prod/rel/git_foil/bin/git-foil filter --process < /dev/null
```

### Quality Gates

Before merging:
- ✅ All unit tests pass
- ✅ All integration tests pass
- ✅ Code coverage >80%
- ✅ Credo (no warnings)
- ✅ Dialyzer (no errors)
- ✅ Release builds successfully
- ✅ Performance benchmarks meet targets

Before releasing:
- ✅ All quality gates pass
- ✅ End-to-end tests pass
- ✅ Manual testing on macOS + Linux
- ✅ Documentation updated
- ✅ Changelog updated
- ✅ Version bumped

---

## Distribution & Packaging

### Target Platforms (v0.9)

| Platform | Architecture | Support Level | Package Format |
|----------|--------------|---------------|----------------|
| macOS | arm64 (M1+) | Primary | Homebrew |
| macOS | x86_64 (Intel) | Primary | Homebrew |
| Linux | x86_64 | Primary | Tarball |
| Linux | arm64 (aarch64) | Secondary | Tarball |
| Windows | x86_64 | Deferred to v1.0 | N/A |

### Installation Methods

**1. Homebrew (macOS - Recommended)**
```bash
brew tap code-of-kai/git-foil
brew install git-foil
```

**2. Manual Installation (macOS/Linux)**
```bash
# Download release
curl -LO https://github.com/code-of-kai/git-foil/releases/download/v0.9.0/git-foil-0.9.0-$(uname -s)-$(uname -m).tar.gz

# Extract
tar -xzf git-foil-0.9.0-*.tar.gz

# Install
sudo mkdir -p /usr/local/lib
sudo cp -r git_foil /usr/local/lib/
sudo ln -sf /usr/local/lib/git_foil/bin/git-foil /usr/local/bin/

# Verify
git-foil --version
```

**3. From Source (Development)**
```bash
git clone https://github.com/code-of-kai/git-foil.git
cd git-foil
mix deps.get
MIX_ENV=prod mix release
sudo cp -r _build/prod/rel/git_foil /usr/local/lib/
sudo ln -sf /usr/local/lib/git_foil/bin/git-foil /usr/local/bin/
```

### Directory Structure

```
/usr/local/lib/git_foil/
├── bin/
│   ├── git-foil              # Main executable
│   └── git-foil.bat          # Windows wrapper (v1.0+)
├── erts-15.0/                # Erlang Runtime System
│   └── bin/
│       └── beam.smp
├── lib/
│   ├── git_foil-0.9.0/
│   │   ├── ebin/             # BEAM bytecode
│   │   └── priv/
│   │       └── native/       # NIFs
│   │           ├── libaegis_nif.so
│   │           ├── libascon_nif.so
│   │           ├── libschwaemm_nif.so
│   │           ├── libdeoxys_nif.so
│   │           └── libchacha20poly1305_nif.so
│   └── [other dependencies...]
└── releases/
    └── 0.9.0/
        ├── start_erl.data
        └── sys.config

/usr/local/bin/
└── git-foil -> /usr/local/lib/git_foil/bin/git-foil

/usr/local/share/man/man1/
├── git-foil.1
├── git-foil-init.1
└── git-foil-key.1
```

### Release Artifacts

**Per-platform releases:**
- `git-foil-0.9.0-Darwin-arm64.tar.gz` (macOS M1+)
- `git-foil-0.9.0-Darwin-x86_64.tar.gz` (macOS Intel)
- `git-foil-0.9.0-Linux-x86_64.tar.gz` (Linux)
- `git-foil-0.9.0-Linux-aarch64.tar.gz` (Linux ARM)

**NIFs (precompiled):**
- `nifs-aarch64-apple-darwin.tar.gz`
- `nifs-x86_64-apple-darwin.tar.gz`
- `nifs-x86_64-unknown-linux-gnu.tar.gz`
- `nifs-aarch64-unknown-linux-gnu.tar.gz`

**Checksums:**
- `SHA256SUMS.txt`

### Release Process

**1. Pre-release:**
```bash
# Bump version
vi mix.exs  # Update @version
vi CHANGELOG.md  # Document changes

# Tag
git tag -a v0.9.0 -m "Release v0.9.0"
git push origin v0.9.0
```

**2. Build releases (CI):**
- CI builds per-platform releases
- NIFs compiled for each target
- Checksums generated
- Artifacts uploaded to GitHub Releases

**3. Post-release:**
```bash
# Update Homebrew formula
cd homebrew-git-foil
vi Formula/git-foil.rb  # Update version, URL, SHA256
git commit -am "Bump to v0.9.0"
git push

# Announce
# - GitHub Releases page
# - Twitter/social media
# - Update documentation
```

---

## Migration Path

### From v0.8 (Broken Escript) to v0.9 (Mix Release)

**User Impact:**
- **Breaking:** Installation location changes
- **Breaking:** Git config values change (adds process filter)
- **Compatible:** Existing `.git/git_foil/master.key` migrated automatically
- **Compatible:** Existing `.gitattributes` unchanged

**Migration Steps:**

#### Step 1: Remove Old Escript
```bash
# Find old escript
which git-foil-dev  # Or git-foil

# Remove it
rm ~/.asdf/installs/elixir/*/escripts/git-foil*
# Or: rm /usr/local/bin/git-foil (if installed globally)
```

#### Step 2: Install v0.9
```bash
# Via Homebrew
brew install code-of-kai/git-foil/git-foil

# Or manually
curl -LO https://github.com/code-of-kai/git-foil/releases/download/v0.9.0/git-foil-0.9.0-$(uname -s)-$(uname -m).tar.gz
tar -xzf git-foil-0.9.0-*.tar.gz
sudo cp -r git_foil /usr/local/lib/
sudo ln -sf /usr/local/lib/git_foil/bin/git-foil /usr/local/bin/
```

#### Step 3: Migrate Existing Repository
```bash
cd /path/to/your/repo

# Run migration
git-foil init --migrate

# What this does:
# 1. Reads old master.key
# 2. Generates random KID
# 3. Creates keys.json with KID mapping
# 4. Updates Git config to use process filter
# 5. Backs up old config
# 6. Baseline encrypts tracked files with new format
```

**Migration Details:**

```elixir
defmodule GitFoil.Commands.Init do
  def run(opts) do
    migrate = Keyword.get(opts, :migrate, false)

    if migrate do
      migrate_from_v08()
    else
      # Normal init
    end
  end

  defp migrate_from_v08 do
    IO.puts("🔄  Migrating from v0.8 to v0.9...")

    # 1. Check for old master.key
    old_key_path = ".git/git_foil/master.key"

    unless File.exists?(old_key_path) do
      {:error, "No v0.8 key found. Use 'git-foil init' for fresh install."}
    end

    # 2. Read old key
    IO.puts("   Reading v0.8 key...")
    {:ok, old_key_binary} = File.read(old_key_path)
    old_keypair = :erlang.binary_to_term(old_key_binary)

    # 3. Generate KID for old key
    kid = GitFoil.KeyManager.Generator.generate_kid()
    IO.puts("   Assigned KID: #{kid}")

    # 4. Create new key store
    store = %{
      version: 1,
      active_kid: kid,
      keys: %{
        kid => %{
          alg: "six-layer-v1",
          created_at: DateTime.utc_now(),
          keypair: old_keypair
        }
      }
    }

    GitFoil.KeyManager.Store.save(store)
    IO.puts("   ✓ Created keys.json")

    # 5. Backup old key
    backup_path = "#{old_key_path}.v08.backup"
    File.rename(old_key_path, backup_path)
    IO.puts("   ✓ Backed up old key to #{backup_path}")

    # 6. Update Git config
    executable_path = get_executable_path()
    configure_git_filters(executable_path)
    IO.puts("   ✓ Updated Git filter configuration")

    # 7. Re-encrypt all tracked files with new format (adds headers)
    IO.puts("\n   Re-encrypting files with new format...")
    {:ok, files} = get_encrypted_files()

    Enum.each(files, fn file ->
      # Read plaintext from working directory
      {:ok, plaintext} = File.read(file)

      # Encrypt with new format (includes HeaderV1)
      {:ok, encrypted} = encrypt_with_header(plaintext, kid, file)

      # Write back
      File.write!(file, encrypted)
    end)

    # 8. Stage changes
    System.cmd("git", ["add", "."])

    IO.puts("\n✅  Migration complete!")
    IO.puts("")
    IO.puts("📋  What changed:")
    IO.puts("   • Git filter now uses long-running process (faster)")
    IO.puts("   • Key stored in keys.json with KID: #{kid}")
    IO.puts("   • All files re-encrypted with new header format")
    IO.puts("   • Old key backed up to #{backup_path}")
    IO.puts("")
    IO.puts("📌  Next steps:")
    IO.puts("   1. Test encryption: git-foil audit")
    IO.puts("   2. Commit changes: git commit -m 'Migrate to GitFoil v0.9'")
    IO.puts("   3. (Optional) Remove old key backup: rm #{backup_path}")

    {:ok, ""}
  end
end
```

#### Step 4: Verify Migration
```bash
# Check key store
git-foil key list

# Audit repository
git-foil audit

# Test encryption
echo "test" > test-secret.txt
git add test-secret.txt
git commit -m "Test v0.9 encryption"
git show HEAD:test-secret.txt | head -c 45 | xxd
# Should show "GFO1" magic + KID + alg + nonce

# Verify decryption
git checkout HEAD -- test-secret.txt
cat test-secret.txt  # Should be "test"
```

**Rollback Plan:**

If migration fails or v0.9 has issues:

```bash
# 1. Restore old key
cp .git/git_foil/master.key.v08.backup .git/git_foil/master.key

# 2. Restore old Git config
git config filter.gitfoil.process ""
git config filter.gitfoil.clean "<old-escript-path> clean %f"
git config filter.gitfoil.smudge "<old-escript-path> smudge %f"

# 3. Restore old escript
# (Re-download or rebuild v0.8)

# 4. Reset working directory
git checkout HEAD -- .
```

---

## Performance Targets

### Baseline Measurements (Theoretical)

| Operation | Time (ms) | Notes |
|-----------|-----------|-------|
| **Cold start** | | |
| VM boot | ~800 | BEAM startup |
| NIF loading (6x) | ~150 | Rust .so files |
| Key loading | ~50 | Read keys.json |
| **Total cold start** | **~1000ms** | One-time cost |
| | | |
| **Per-file (warm)** | | |
| Six-layer encrypt | ~15 | Crypto only |
| Header encode | <1 | Binary construction |
| I/O overhead | ~5 | pkt-line, buffers |
| **Total per-file** | **~20ms** | Target for p95 |
| | | |
| **Bulk operations** | | |
| 100 files | ~2 sec | 20ms × 100 |
| 1000 files | ~20 sec | 20ms × 1000 |
| 3000 files | **~60 sec** | **Target** |

### v0.9 Performance Goals

| Metric | Target | Stretch Goal | Rationale |
|--------|--------|--------------|-----------|
| Cold start | <1000ms | <500ms | One-time cost, acceptable |
| Per-file (p50) | <15ms | <10ms | Crypto overhead |
| Per-file (p95) | **<20ms** | **<15ms** | **Primary goal** |
| Per-file (p99) | <30ms | <25ms | Tail latency |
| 3000 files | **<60s** | **<45s** | **User experience** |
| Memory (baseline) | <30MB | <20MB | Resident set |
| Memory (3000 files) | <50MB | <40MB | No leaks |

### Optimization Techniques

**1. NIF Optimization:**
```rust
// Mark NIFs as dirty CPU-bound
#[rustler::nif(schedule = "DirtyCpu")]
fn encrypt(key: Binary, nonce: Binary, plaintext: Binary) -> Result<Binary, Error> {
    // Heavy crypto work doesn't block schedulers
}

// Reuse allocations
static mut BUFFER: Vec<u8> = Vec::new();

#[rustler::nif]
fn encrypt_reuse(key: Binary, nonce: Binary, plaintext: Binary) -> Result<Binary, Error> {
    unsafe {
        BUFFER.clear();
        BUFFER.reserve(plaintext.len() + 16);  // Amortize allocations
        // ... crypto work into BUFFER
        Ok(Binary::from_slice(&BUFFER))
    }
}
```

**2. BEAM Tuning:**
```bash
# Optimize for crypto workload
export ERL_FLAGS="-noshell -noinput +sbwt none +sbwtdcpu none +sbwtdio none +sssdio 0"

# Increase dirty CPU schedulers (default: 10)
export ERL_FLAGS="$ERL_FLAGS +SDcpu 16"

# Tune for throughput over latency
export ERL_FLAGS="$ERL_FLAGS +K true +A 4"
```

**3. Concurrency:**
```elixir
# Use Task.Supervisor for parallel crypto
defmodule GitFoil.Filter.ProcessProtocol do
  def handle_request(:clean, headers, data) do
    Task.Supervisor.async_nolink(GitFoil.TaskSup, fn ->
      encrypt(data, headers["pathname"])
    end)
    |> Task.await(:infinity)
  end
end

# Git can send multiple requests concurrently
# Process them in parallel (up to dirty scheduler limit)
```

**4. Memory Efficiency:**
```elixir
# Stream large blobs instead of loading entire file
defmodule GitFoil.Filter.PktLine do
  def read_blob_stream(device) do
    Stream.resource(
      fn -> device end,
      fn dev ->
        case read_packet(dev) do
          {:ok, chunk} when is_binary(chunk) -> {[chunk], dev}
          :flush -> {:halt, dev}
        end
      end,
      fn dev -> dev end
    )
  end
end

# Encrypt in chunks (for future large file support)
defmodule GitFoil.Crypto.Engine do
  def encrypt_stream(stream, key, kid) do
    # Process in 64KB chunks
    Stream.chunk_every(stream, 65536)
    |> Stream.map(&encrypt_chunk(&1, key))
  end
end
```

### Profiling & Monitoring

**Development profiling:**
```elixir
# lib/git_foil/telemetry.ex
defmodule GitFoil.Telemetry do
  def setup do
    :telemetry.attach_many(
      "git-foil-handler",
      [
        [:git_foil, :filter, :clean, :start],
        [:git_foil, :filter, :clean, :stop],
        [:git_foil, :crypto, :encrypt, :start],
        [:git_foil, :crypto, :encrypt, :stop]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:git_foil, :filter, :clean, :stop], measurements, metadata, _) do
    if System.get_env("GIT_FOIL_DEBUG") do
      IO.puts(:stderr, "clean: #{metadata.path} in #{measurements.duration / 1_000_000}ms")
    end
  end
end
```

**Benchmarking script:**
```bash
#!/bin/bash
# scripts/benchmark.sh

echo "=== GitFoil v0.9 Performance Benchmark ==="
echo ""

# Setup test repo
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
git init

# Configure GitFoil
git-foil init --force

# Generate test files
echo "Generating 3000 test files..."
for i in {1..3000}; do
  echo "secret data $i" > "file$i.env"
done

# Benchmark: git add
echo ""
echo "Benchmarking: git add (3000 files)"
time git add *.env

# Benchmark: git checkout
echo ""
echo "Benchmarking: git commit + checkout"
git commit -m "Test"
time git checkout HEAD -- .

# Cleanup
cd /
rm -rf "$TEMP_DIR"
```

---

## Future Roadmap (v1.0+)

### Deferred Features

**1. Key Rotation with History Rewrite**
```bash
git-foil rekey --to <new-kid> [--pathspec ...]     # Working tree only
git-foil rekey-history --to <new-kid> --all --force # Rewrite history
```

**Why deferred:** Complex, requires git-filter-repo integration, no immediate need

**2. Windows Support**
- Build NIFs for Windows (x86_64-pc-windows-msvc)
- Test process filter on Windows Git
- Package as .msi installer

**Why deferred:** Limited user base on Windows for v0.9, adds complexity

**3. Multi-key State Management**
```json
{
  "keys": {
    "abc123": {
      "state": "active",      // Current encryption key
      "alg": "six-layer-v1"
    },
    "def456": {
      "state": "decrypt-only", // Can decrypt, not encrypt
      "alg": "six-layer-v1",
      "deprecated_at": "2025-12-01"
    },
    "old789": {
      "state": "retired",      // Scheduled for removal
      "alg": "six-layer-v1",
      "delete_after": "2026-01-01"
    }
  }
}
```

**Why deferred:** No v0.9 users have history requiring rotation yet

**4. Advanced Packaging**
- Debian/Ubuntu .deb packages
- RedHat/Fedora .rpm packages
- Arch Linux AUR package
- Docker image
- Snap package

**Why deferred:** Homebrew + tarball sufficient for v0.9 audience

**5. Performance: Batch Encryption**
```elixir
# Process multiple files in parallel with pooling
defmodule GitFoil.Filter.BatchProcessor do
  use GenServer

  # Queue requests, process in batches of 10
  def handle_request(request) do
    # Add to queue
    # When queue reaches 10, process all in parallel
    # Return results in order
  end
end
```

**Why deferred:** Process filter already fast enough (<20ms target)

**6. Telemetry & Observability**
```elixir
# Metrics export for monitoring
GitFoil.Telemetry.setup()
# Exports to StatsD/Prometheus:
# - git_foil.filter.clean.duration
# - git_foil.filter.smudge.duration
# - git_foil.crypto.encrypt.count
# - git_foil.memory.bytes
```

**Why deferred:** Not needed for individual developer use (v0.9 target)

**7. Remote Key Storage**
```bash
# Fetch keys from remote keyserver
git config gitfoil.keystore "https://keyserver.example.com/keys"
git config gitfoil.keystore.auth "bearer:$TOKEN"
```

**Why deferred:** Security complexity, most users prefer local keys

---

## Appendices

### Appendix A: Git Process Filter Protocol Reference

**Official Documentation:**
- Git Documentation: https://git-scm.com/docs/gitattributes#_long_running_filter_process
- Git v2.11.0 release notes: https://github.com/git/git/blob/master/Documentation/RelNotes/2.11.0.txt

**Protocol Specification:**

**Handshake:**
```
Git → filter:    (none, filter starts)
filter → Git:    packet: version=2
filter → Git:    packet: capability=clean
filter → Git:    packet: capability=smudge
filter → Git:    packet: capability=delay  (optional)
filter → Git:    flush-pkt
```

**Request (clean/smudge):**
```
Git → filter:    packet: command=clean|smudge
Git → filter:    packet: pathname=<path>
Git → filter:    packet: can-delay=1  (optional)
Git → filter:    flush-pkt
Git → filter:    <binary data>
Git → filter:    flush-pkt
```

**Response:**
```
filter → Git:    <binary data>
filter → Git:    flush-pkt
filter → Git:    packet: status=success|error
filter → Git:    packet: error=<message>  (if status=error)
filter → Git:    flush-pkt
```

**Pkt-line Format:**
```
<4-byte-hex-length><payload>

Examples:
0011version=2\n       → length=0x0011 (17 bytes including length)
0000                  → flush packet
0001                  → delim packet
0002                  → response end packet
```

**Error Handling:**
- Filter process crashes → Git falls back to no filter
- Filter returns error → Git aborts operation
- Filter returns invalid → Git treats as error

**Performance Notes:**
- Git may pipeline requests (send multiple before reading responses)
- Filter should handle concurrent requests if possible
- Git may kill filter after timeout (default: 2 minutes idle)

### Appendix B: HeaderV1 Wire Format

**Binary Layout:**
```
Offset | Size | Field  | Type        | Description
-------|------|--------|-------------|----------------------------------
0      | 4    | magic  | char[4]     | "GFO1" (0x47 0x46 0x4F 0x31)
4      | 8    | kid    | hex string  | Key ID (16 hex digits)
12     | 1    | alg    | uint8       | Algorithm enum
13     | 32   | nonce  | bytes       | Random nonce
-------|------|--------|-------------|----------------------------------
Total: 45 bytes
```

**Example (hex dump):**
```
00000000: 4746 4f31 6538 6432 6231 6634 6133 6339  GFO1e8d2b1f4a3c9
00000010: 6437 6532 01a7 b3c2 d8e4 f1a5 c7d9 e3f2  d7e2............
00000020: a8b4 c6d1 e5f3 a2b8 c4d0 e6f4 a1b7 c3d2  ................
00000030: e7f5 a3b9 c5d3 e9f7 a4ba c8d4 eb         .............
```

**Parsing Logic:**
```elixir
def decode(<<
  "GFO1",
  kid::binary-size(8),
  alg::8,
  nonce::binary-size(32),
  rest::binary
>>) do
  header = %Header{
    magic: "GFO1",
    kid: kid,
    alg: alg,
    nonce: nonce
  }
  {:ok, header, rest}
end

def decode(_), do: {:error, :invalid_header}
```

**Validation Rules:**
- `magic` MUST be exactly "GFO1"
- `kid` MUST be 8 bytes (16 hex characters when encoded)
- `alg` MUST be a known algorithm (0x01 for six-layer-v1)
- `nonce` MUST be 32 bytes of randomness
- Total header MUST be 45 bytes

### Appendix C: Algorithm Enum Values

```
0x00 = Reserved (invalid)
0x01 = six-layer-v1 (current)
       Layers: AES-256-GCM
               AEGIS-256
               Schwaemm256-256
               Deoxys-II-256
               Ascon-128a
               ChaCha20-Poly1305

0x02-0x0F = Reserved for six-layer variants
0x10-0x1F = Reserved for reduced-layer variants (3-layer, 4-layer)
0x20-0xFF = Reserved for future algorithms
```

### Appendix D: Error Codes & Messages

**User-Facing Errors:**
```
E001: GitFoil not initialized - run 'git-foil init' first
E002: Crypto library not loaded (AEGIS/Ascon/etc)
E003: Invalid encryption header (corrupted blob)
E004: Key not found: <kid>
E005: Invalid password
E006: Git repository not found
E007: Process filter protocol error
E008: NIF loading failed
```

**Internal Errors (logged to stderr with DEBUG):**
```
I001: NIF warm-up completed in Xms
I002: Loaded key <kid>
I003: Encrypted <file> in Xms
W001: Slow encryption detected: <file> took Xms
W002: High memory usage: XMB
```

### Appendix E: Development Workflow

**Daily Development:**
```bash
# Compile and run tests
mix test

# Run specific test
mix test test/git_foil/crypto/header_test.exs:42

# Run with coverage
mix test --cover

# Type checking
mix dialyzer

# Linting
mix credo --strict

# Format code
mix format
```

**Testing Process Filter Locally:**
```bash
# Build release
MIX_ENV=prod mix release

# Create test repo
cd /tmp
rm -rf test-repo
git init test-repo
cd test-repo

# Configure GitFoil (point to local build)
~/.../git-foil/_build/prod/rel/git_foil/bin/git-foil init

# Verify config
git config filter.gitfoil.process
# Should show: /path/to/_build/prod/rel/git_foil/bin/git-foil filter --process

# Test encryption
echo "secret" > test.env
git add test.env
git commit -m "Test"

# Verify encrypted
git show HEAD:test.env | xxd | head -n 5

# Verify decryption
git checkout HEAD -- test.env
cat test.env  # Should show "secret"
```

**Debugging Process Filter:**
```bash
# Enable debug logging
export GIT_FOIL_DEBUG=1

# Run git add with trace
GIT_TRACE=1 git add test.env

# Manual protocol test
echo -e "0023version=2\n0018capability=clean\n0000" | \
  git-foil filter --process | xxd

# Check memory usage
ps aux | grep git-foil
```

### Appendix F: Security Considerations

**Threat Model:**

**In Scope:**
- Confidentiality of data at rest (Git repository)
- Protection against cryptographic algorithm breaks (six layers)
- Quantum computer resistance (post-quantum Kyber1024)

**Out of Scope:**
- Protection of working directory (plaintext)
- Protection against malicious collaborators with key access
- Protection against compromised Git server (they see ciphertext only)
- Protection against OS-level key extraction (memory scraping, etc.)

**Security Properties:**

**1. Key Management:**
- Keys never committed to Git (in .gitignore)
- Keys stored with 0600 permissions (owner only)
- Keys can be password-protected (optional)
- Key export encrypted with user password

**2. Cryptographic:**
- Six independent layers (no shared weaknesses)
- Per-blob nonce (no nonce reuse)
- Authenticated encryption (AEAD in all layers)
- Post-quantum keypair (Kyber1024)

**3. Process Isolation:**
- Filter runs as user's process (same as Git)
- No network access required
- No elevated permissions needed
- Long-running process reduces attack surface vs. repeated spawns

**Known Limitations:**

**1. Working Directory Plaintext:**
- Decrypted files visible on disk
- No protection against local file access
- Mitigation: Use full-disk encryption (FileVault, LUKS)

**2. Memory Exposure:**
- Keys in BEAM VM memory (unencrypted)
- Plaintext briefly in memory during clean/smudge
- Mitigation: OS memory protection, swap encryption

**3. Side Channels:**
- Timing attacks possible (but unlikely in Git context)
- Cache timing attacks on NIFs
- Mitigation: Constant-time crypto in NIFs where feasible

**4. Key Compromise:**
- If key stolen, all data decryptable
- Mitigation: Password-protect keys, rotate regularly

**Audit Recommendations:**

For production use, consider:
- [ ] Third-party security audit of crypto implementation
- [ ] Fuzzing of pkt-line parser
- [ ] Memory safety audit of Rust NIFs
- [ ] Side-channel analysis
- [ ] Formal verification of critical paths

---

## Changelog

### v0.9.0 (Target: Q4 2025)

**Major Changes:**
- **Architecture:** Replaced escript with Mix Release
- **Performance:** Implemented Git process filter protocol (100x faster)
- **Format:** Added HeaderV1 with KID for key rotation support
- **NIFs:** Precompiled Rust NIFs for easy installation
- **Distribution:** Homebrew support for macOS

**Breaking Changes:**
- Installation location changed to `/usr/local/lib/git_foil/`
- Git config now uses `filter.gitfoil.process` (with fallback)
- Key storage moved to `keys.json` format (with migration)
- Blob format includes 45-byte header (old blobs not readable)

**Migration Required:**
- Run `git-foil init --migrate` to upgrade from v0.8
- All files will be re-encrypted with new header format
- Commit changes after migration

**New Commands:**
- `git-foil filter --process` - Long-running filter mode
- `git-foil key generate` - Generate new encryption key
- `git-foil key activate <kid>` - Switch active key
- `git-foil key list` - Show all keys
- `git-foil key export` - Backup keys (encrypted)
- `git-foil key import` - Restore keys
- `git-foil audit` - Scan repo for KID usage

**Performance:**
- Cold start: ~1000ms (one-time)
- Per-file (warm): ~20ms (p95)
- 3000 files: ~60 seconds (vs. hours in v0.8)

**Fixes:**
- Fixed NIF loading (escripts fundamentally broken)
- Fixed ugly error messages (stack traces)
- Added proper error handling throughout

**Known Issues:**
- Windows not yet supported (deferred to v1.0)
- History rewrite tools not included (deferred to v1.0)

---

## Authors & Acknowledgments

**Primary Author:**
- Kai Taylor (@code-of-kai)

**Contributors:**
- [List of contributors to be added]

**Special Thanks:**
- Claude AI for architectural guidance
- Git maintainers for process filter protocol
- Rustler team for excellent Elixir-Rust integration
- Post-quantum cryptography researchers

**Cryptographic Libraries:**
- PQClean: Post-quantum Kyber1024 implementation
- Rustler: Elixir NIFs in Rust
- OpenSSL: AES-256-GCM baseline
- Custom NIFs: AEGIS, Ascon, Schwaemm, Deoxys, ChaCha20

---

## License

MIT License - See LICENSE file for details

---

**Document Version:** 1.0
**Last Updated:** 2025-10-14
**Status:** Planning Phase
**Next Review:** After Phase 1 completion
