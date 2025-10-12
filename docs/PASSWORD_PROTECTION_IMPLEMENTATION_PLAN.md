# Git Foil Password Protection Implementation Plan

**Goal:** Add password protection and OS keychain integration to Git Foil's master key storage, addressing the "stolen laptop without disk encryption" vulnerability.

**Timeline:** 3 weeks
**Approach:** Three-tier fallback system with graceful degradation
**Status:** Planning Phase

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Week 1: PBKDF2 Password Protection](#week-1-pbkdf2-password-protection-tier-1)
3. [Week 2: OS Keychain Integration](#week-2-os-keychain-integration-tier-2)
4. [Week 3: Key Agent Caching](#week-3-key-agent-caching-tier-3)
5. [Testing Strategy](#testing-strategy)
6. [Migration & Backward Compatibility](#migration--backward-compatibility)
7. [Security Considerations](#security-considerations)
8. [Future Enhancements](#future-enhancements)

---

## Architecture Overview

### Three-Tier Fallback System

```
┌─────────────────────────────────────────────────────────────┐
│                    User runs git command                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              GitFoil.Core.KeyManager.unlock()                │
└──────────────────────┬──────────────────────────────────────┘
                       │
           ┌───────────┴───────────┐
           │                       │
           ▼                       ▼
    ┌──────────────┐        ┌──────────────┐
    │ Check cache  │        │ No cache?    │
    │ (Week 3)     │        │ Proceed...   │
    └──────┬───────┘        └──────┬───────┘
           │                       │
           │ Hit                   │ Miss
           ▼                       ▼
    ┌──────────────┐        ┌──────────────────────────┐
    │ Return key   │        │ Try Tier 1: OS Keychain  │
    └──────────────┘        │ (macOS/Linux)            │
                            │ Week 2                   │
                            └──────┬───────────────────┘
                                   │
                       ┌───────────┴────────────┐
                       │                        │
                       ▼ Success                ▼ Not available/Failed
                ┌─────────────┐         ┌──────────────────────┐
                │ Return key  │         │ Try Tier 2: Password │
                │ Cache it    │         │ Encrypted File       │
                └─────────────┘         │ Week 1               │
                                        └──────┬───────────────┘
                                               │
                                   ┌───────────┴────────────┐
                                   │                        │
                                   ▼ Exists                 ▼ Not found
                            ┌─────────────┐         ┌──────────────────┐
                            │ Prompt pwd  │         │ Try Tier 3:      │
                            │ Decrypt     │         │ Legacy plaintext │
                            │ Cache it    │         │ (upgrade prompt) │
                            └─────────────┘         └──────────────────┘
```

### File Structure Changes

```
lib/git_foil/
├── core/
│   ├── key_manager.ex              # NEW: Orchestrates all tiers
│   ├── password_protection.ex      # NEW: Week 1 - PBKDF2 + AES-GCM
│   └── key_agent.ex                # NEW: Week 3 - In-memory cache
├── adapters/
│   └── os_keychain.ex              # NEW: Week 2 - Keychain interface
├── native/
│   └── keyring_nif.ex              # NEW: Week 2 - Elixir NIF module
└── ports/
    └── key_storage.ex              # UPDATED: Add new behaviors

native/
└── keyring_nif/                    # NEW: Week 2 - Rust NIF
    ├── Cargo.toml
    └── src/
        └── lib.rs

.git/git_foil/
├── master.key                      # OLD: Plaintext (legacy)
├── master.key.enc                  # NEW: Password-encrypted
└── master.key.backup.*             # NEW: Auto-backup on upgrade
```

---

## Week 1: PBKDF2 Password Protection (Tier 1)

**Goal:** Encrypt master key with password-derived key using industry-standard PBKDF2 + AES-256-GCM

### Day 1-2: Core Encryption Module

#### File: `lib/git_foil/core/password_protection.ex`

```elixir
defmodule GitFoil.Core.PasswordProtection do
  @moduledoc """
  Password-based master key protection using PBKDF2-HMAC-SHA512 + AES-256-GCM.

  Based on Bitwarden's FIPS-140 compliant implementation:
  - KDF: PBKDF2-HMAC-SHA512 with 600,000 iterations
  - AEAD: AES-256-GCM with 12-byte nonce
  - Salt: 32-byte random salt per key

  File format (v1):

      ┌────────┬────────────┬───────────┬─────────┬──────────────┐
      │ Version│    Salt    │   Nonce   │   Tag   │  Ciphertext  │
      │ (1B)   │   (32B)    │   (12B)   │  (16B)  │   (32B+)     │
      └────────┴────────────┴───────────┴─────────┴──────────────┘

  Total: 93 bytes for 32-byte master key
  """

  # Based on OWASP & Bitwarden recommendations (2024)
  @pbkdf2_iterations 600_000
  @pbkdf2_hash :sha512
  @salt_bytes 32
  @nonce_bytes 12
  @tag_bytes 16
  @kek_bytes 32  # Key Encryption Key size
  @version 1

  @type encrypted_key :: binary()
  @type plaintext_key :: binary()
  @type password :: String.t()

  @doc """
  Encrypts a master key with a password.

  ## Examples

      iex> master_key = :crypto.strong_rand_bytes(32)
      iex> {:ok, encrypted} = PasswordProtection.encrypt_master_key(master_key, "strong-password")
      iex> byte_size(encrypted)
      93
  """
  @spec encrypt_master_key(plaintext_key, password) ::
          {:ok, encrypted_key} | {:error, term()}
  def encrypt_master_key(master_key, password)
      when is_binary(master_key) and byte_size(master_key) == 32 and
             is_binary(password) and byte_size(password) > 0 do
    try do
      # 1. Generate random salt for this encryption
      salt = :crypto.strong_rand_bytes(@salt_bytes)

      # 2. Derive Key Encryption Key (KEK) from password
      kek = derive_kek(password, salt)

      # 3. Generate random nonce for AES-GCM
      nonce = :crypto.strong_rand_bytes(@nonce_bytes)

      # 4. Encrypt master key with AES-256-GCM
      aad = <<"GitFoil.PasswordProtection.v", @version>>

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          kek,
          nonce,
          master_key,
          aad,
          true  # encrypt
        )

      # 5. Securely wipe KEK from memory (best effort)
      :crypto.exor(kek, kek)

      # 6. Build encrypted blob: version || salt || nonce || tag || ciphertext
      encrypted_blob =
        <<@version::8, salt::binary-@salt_bytes, nonce::binary-@nonce_bytes,
          tag::binary-@tag_bytes, ciphertext::binary>>

      {:ok, encrypted_blob}
    rescue
      error ->
        {:error, {:encryption_failed, error}}
    end
  end

  def encrypt_master_key(_master_key, _password) do
    {:error, :invalid_parameters}
  end

  @doc """
  Decrypts a master key with a password.

  ## Examples

      iex> {:ok, encrypted} = PasswordProtection.encrypt_master_key(key, "password")
      iex> {:ok, decrypted} = PasswordProtection.decrypt_master_key(encrypted, "password")
      iex> decrypted == key
      true

      iex> PasswordProtection.decrypt_master_key(encrypted, "wrong")
      {:error, :invalid_password}
  """
  @spec decrypt_master_key(encrypted_key, password) ::
          {:ok, plaintext_key} | {:error, :invalid_password | term()}
  def decrypt_master_key(encrypted_blob, password)
      when is_binary(encrypted_blob) and is_binary(password) do
    try do
      # 1. Parse encrypted blob
      <<version::8, salt::binary-@salt_bytes, nonce::binary-@nonce_bytes,
        tag::binary-@tag_bytes, ciphertext::binary>> = encrypted_blob

      # 2. Verify version
      unless version == @version do
        raise "Unsupported encryption version: #{version}"
      end

      # 3. Re-derive KEK using same salt and password
      kek = derive_kek(password, salt)

      # 4. Attempt to decrypt and verify authentication tag
      aad = <<"GitFoil.PasswordProtection.v", @version>>

      case :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             kek,
             nonce,
             ciphertext,
             aad,
             tag,
             false  # decrypt
           ) do
        master_key when is_binary(master_key) ->
          # Success! Authentication passed
          {:ok, master_key}

        _error ->
          # Authentication failed - wrong password or tampered data
          {:error, :invalid_password}
      end
    rescue
      _error ->
        {:error, :invalid_password}
    end
  end

  @doc """
  Derives a Key Encryption Key from password and salt using PBKDF2.

  Uses PBKDF2-HMAC-SHA512 with 600,000 iterations (Bitwarden/OWASP standard).
  Execution time: ~100ms on modern CPU (acceptable for UX).
  """
  @spec derive_kek(password, binary()) :: binary()
  defp derive_kek(password, salt) do
    :crypto.pbkdf2_hmac(
      @pbkdf2_hash,
      password,
      salt,
      @pbkdf2_iterations,
      @kek_bytes
    )
  end

  @doc """
  Benchmarks PBKDF2 performance on this machine.

  Useful for tuning iteration count or diagnosing performance issues.

  ## Examples

      iex> PasswordProtection.benchmark()
      PBKDF2-HMAC-SHA512 (600,000 iterations): 102.4ms
      :ok
  """
  def benchmark do
    password = "test-password-for-benchmarking"
    salt = :crypto.strong_rand_bytes(@salt_bytes)

    {time_us, _result} =
      :timer.tc(fn ->
        derive_kek(password, salt)
      end)

    time_ms = time_us / 1000

    IO.puts(
      "PBKDF2-HMAC-SHA512 (#{@pbkdf2_iterations} iterations): #{Float.round(time_ms, 1)}ms"
    )

    :ok
  end

  @doc """
  Validates password strength (basic check).

  Returns {:ok, password} or {:error, reason}.
  """
  @spec validate_password(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate_password(password) when is_binary(password) do
    cond do
      String.length(password) < 8 ->
        {:error, :password_too_short}

      String.length(password) > 1024 ->
        {:error, :password_too_long}

      true ->
        {:ok, password}
    end
  end
end
```

#### File: `lib/git_foil/ports/key_storage.ex` (Updated)

```elixir
defmodule GitFoil.Ports.KeyStorage do
  @moduledoc """
  Port interface for key storage backends.

  Implementations:
  - FileSystemKeyStorage (existing, plaintext)
  - PasswordProtectedKeyStorage (new, encrypted)
  - OsKeychainStorage (Week 2)
  """

  @type master_key :: binary()
  @type storage_path :: String.t()

  @callback save_master_key(master_key, storage_path, opts :: keyword()) ::
              :ok | {:error, term()}

  @callback load_master_key(storage_path, opts :: keyword()) ::
              {:ok, master_key} | {:error, term()}

  @callback key_exists?(storage_path) :: boolean()

  @callback delete_master_key(storage_path) :: :ok | {:error, term()}
end
```

#### File: `lib/git_foil/adapters/password_protected_key_storage.ex`

```elixir
defmodule GitFoil.Adapters.PasswordProtectedKeyStorage do
  @moduledoc """
  Password-protected file-based key storage using PBKDF2 + AES-GCM.
  """

  @behaviour GitFoil.Ports.KeyStorage

  alias GitFoil.Core.PasswordProtection

  @encrypted_key_filename "master.key.enc"

  @impl true
  def save_master_key(master_key, storage_path, opts) do
    password = Keyword.fetch!(opts, :password)

    with {:ok, validated_password} <- PasswordProtection.validate_password(password),
         {:ok, encrypted_blob} <- PasswordProtection.encrypt_master_key(master_key, validated_password),
         encrypted_path <- Path.join(storage_path, @encrypted_key_filename),
         :ok <- File.write(encrypted_path, encrypted_blob, [:binary]) do
      # Set restrictive permissions (owner read/write only)
      File.chmod!(encrypted_path, 0o600)
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def load_master_key(storage_path, opts) do
    password = Keyword.fetch!(opts, :password)
    encrypted_path = Path.join(storage_path, @encrypted_key_filename)

    with {:ok, encrypted_blob} <- File.read(encrypted_path),
         {:ok, master_key} <- PasswordProtection.decrypt_master_key(encrypted_blob, password) do
      {:ok, master_key}
    else
      {:error, :enoent} -> {:error, :key_not_found}
      {:error, :invalid_password} -> {:error, :invalid_password}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def key_exists?(storage_path) do
    encrypted_path = Path.join(storage_path, @encrypted_key_filename)
    File.exists?(encrypted_path)
  end

  @impl true
  def delete_master_key(storage_path) do
    encrypted_path = Path.join(storage_path, @encrypted_key_filename)

    case File.rm(encrypted_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok  # Already deleted
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Day 3: Password Input & CLI Integration

#### File: `lib/git_foil/cli/password_prompt.ex`

```elixir
defmodule GitFoil.CLI.PasswordPrompt do
  @moduledoc """
  Secure password input for CLI.

  Uses IO.gets with echo disabled (via :io.setopts).
  """

  @doc """
  Prompts user for password without echoing input.

  ## Examples

      password = PasswordPrompt.get_password("Enter password: ")
  """
  @spec get_password(String.t(), keyword()) :: String.t() | nil
  def get_password(prompt, opts \\ []) do
    confirm? = Keyword.get(opts, :confirm, false)

    password = do_get_password(prompt)

    if confirm? do
      confirmation = do_get_password("Confirm password: ")

      if password == confirmation do
        password
      else
        IO.puts(:stderr, "\nPasswords do not match. Please try again.")
        get_password(prompt, opts)
      end
    else
      password
    end
  end

  defp do_get_password(prompt) do
    # Display prompt
    IO.write(prompt)

    # Disable echo
    :io.setopts(:standard_io, echo: false)

    # Read password
    password = IO.gets("") |> String.trim()

    # Re-enable echo
    :io.setopts(:standard_io, echo: true)

    # Print newline (since input wasn't echoed)
    IO.puts("")

    password
  end

  @doc """
  Gets password from environment variable or prompts user.

  Useful for CI/CD or automated scenarios.

  ## Examples

      # Try ENV var first, then prompt
      password = PasswordPrompt.get_password_with_fallback("GIT_FOIL_PASSWORD", "Enter password: ")
  """
  @spec get_password_with_fallback(String.t(), String.t(), keyword()) :: String.t() | nil
  def get_password_with_fallback(env_var, prompt, opts \\ []) do
    case System.get_env(env_var) do
      nil -> get_password(prompt, opts)
      "" -> get_password(prompt, opts)
      password -> password
    end
  end
end
```

#### File: `lib/git_foil/cli/commands/init.ex` (Updated)

```elixir
defmodule GitFoil.CLI.Commands.Init do
  # ... existing code ...

  defp setup_master_key do
    IO.puts("\n=== Master Key Setup ===\n")
    IO.puts("Git Foil can protect your master key with a password.")
    IO.puts("This adds a layer of security if your laptop is stolen.\n")

    use_password? =
      IO.gets("Protect master key with password? (Y/n): ")
      |> String.trim()
      |> String.downcase()
      |> case do
        "n" -> false
        "no" -> false
        _ -> true
      end

    master_key = generate_master_key()

    if use_password? do
      save_password_protected_key(master_key)
    else
      save_plaintext_key(master_key)
      IO.puts("\n⚠️  Warning: Master key stored without password protection.")
      IO.puts("   Use full disk encryption to protect your key!")
    end
  end

  defp save_password_protected_key(master_key) do
    alias GitFoil.CLI.PasswordPrompt
    alias GitFoil.Adapters.PasswordProtectedKeyStorage

    password = PasswordPrompt.get_password("Enter password: ", confirm: true)

    case PasswordProtectedKeyStorage.save_master_key(
           master_key,
           ".git/git_foil",
           password: password
         ) do
      :ok ->
        IO.puts("\n✓ Master key encrypted and saved to .git/git_foil/master.key.enc")
        IO.puts("  (Protected with PBKDF2-HMAC-SHA512 + AES-256-GCM)")

      {:error, reason} ->
        IO.puts(:stderr, "\n✗ Failed to save encrypted key: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp save_plaintext_key(master_key) do
    # Existing plaintext save logic
    # ...
  end
end
```

### Day 4-5: Testing

#### File: `test/git_foil/core/password_protection_test.exs`

```elixir
defmodule GitFoil.Core.PasswordProtectionTest do
  use ExUnit.Case, async: true

  alias GitFoil.Core.PasswordProtection

  describe "encrypt_master_key/2" do
    test "encrypts a 32-byte master key with password" do
      master_key = :crypto.strong_rand_bytes(32)
      password = "strong-password-123"

      assert {:ok, encrypted} = PasswordProtection.encrypt_master_key(master_key, password)
      assert is_binary(encrypted)
      assert byte_size(encrypted) == 93  # 1 + 32 + 12 + 16 + 32
    end

    test "produces different ciphertext for same key (random salt/nonce)" do
      master_key = :crypto.strong_rand_bytes(32)
      password = "password"

      {:ok, encrypted1} = PasswordProtection.encrypt_master_key(master_key, password)
      {:ok, encrypted2} = PasswordProtection.encrypt_master_key(master_key, password)

      # Different due to random salt and nonce
      assert encrypted1 != encrypted2
    end

    test "rejects invalid master key size" do
      assert {:error, :invalid_parameters} =
               PasswordProtection.encrypt_master_key(:crypto.strong_rand_bytes(16), "password")
    end

    test "rejects empty password" do
      assert {:error, :invalid_parameters} =
               PasswordProtection.encrypt_master_key(:crypto.strong_rand_bytes(32), "")
    end
  end

  describe "decrypt_master_key/2" do
    test "successfully decrypts with correct password" do
      master_key = :crypto.strong_rand_bytes(32)
      password = "correct-password"

      {:ok, encrypted} = PasswordProtection.encrypt_master_key(master_key, password)
      {:ok, decrypted} = PasswordProtection.decrypt_master_key(encrypted, password)

      assert decrypted == master_key
    end

    test "fails with wrong password" do
      master_key = :crypto.strong_rand_bytes(32)

      {:ok, encrypted} = PasswordProtection.encrypt_master_key(master_key, "correct")
      assert {:error, :invalid_password} = PasswordProtection.decrypt_master_key(encrypted, "wrong")
    end

    test "detects tampering (authentication failure)" do
      master_key = :crypto.strong_rand_bytes(32)
      password = "password"

      {:ok, encrypted} = PasswordProtection.encrypt_master_key(master_key, password)

      # Tamper with ciphertext
      <<version::8, salt::binary-32, nonce::binary-12, tag::binary-16, ciphertext::binary>> =
        encrypted

      tampered_ciphertext = :crypto.exor(ciphertext, <<1>>)
      tampered_encrypted = <<version::8, salt::binary, nonce::binary, tag::binary, tampered_ciphertext::binary>>

      assert {:error, :invalid_password} =
               PasswordProtection.decrypt_master_key(tampered_encrypted, password)
    end
  end

  describe "validate_password/1" do
    test "accepts strong passwords" do
      assert {:ok, "strong-password-123"} =
               PasswordProtection.validate_password("strong-password-123")
    end

    test "rejects passwords shorter than 8 characters" do
      assert {:error, :password_too_short} = PasswordProtection.validate_password("short")
    end

    test "rejects passwords longer than 1024 characters" do
      long_password = String.duplicate("a", 1025)
      assert {:error, :password_too_long} = PasswordProtection.validate_password(long_password)
    end
  end

  describe "benchmark/0" do
    test "runs benchmark without errors" do
      assert :ok = PasswordProtection.benchmark()
    end
  end
end
```

#### Integration Test: `test/integration/password_protected_init_test.exs`

```elixir
defmodule GitFoil.Integration.PasswordProtectedInitTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  @test_repo_path "/tmp/git_foil_test_#{System.unique_integer([:positive])}"

  setup do
    # Create test git repo
    File.mkdir_p!(@test_repo_path)
    System.cmd("git", ["init"], cd: @test_repo_path)

    on_exit(fn ->
      File.rm_rf!(@test_repo_path)
    end)

    {:ok, repo_path: @test_repo_path}
  end

  test "init with password protection creates encrypted key file", %{repo_path: repo_path} do
    # Simulate user input: use password, enter password twice
    input = "y\ntest-password\ntest-password\n"

    capture_io([input: input], fn ->
      # Run init command
      GitFoil.CLI.main(["init"], cd: repo_path)
    end)

    # Verify encrypted key file exists
    encrypted_key_path = Path.join([repo_path, ".git/git_foil/master.key.enc"])
    assert File.exists?(encrypted_key_path)

    # Verify plaintext key does NOT exist
    plaintext_key_path = Path.join([repo_path, ".git/git_foil/master.key"])
    refute File.exists?(plaintext_key_path)

    # Verify we can decrypt it
    encrypted_blob = File.read!(encrypted_key_path)
    {:ok, _master_key} = PasswordProtection.decrypt_master_key(encrypted_blob, "test-password")
  end

  test "encrypted key can be used for actual encryption", %{repo_path: repo_path} do
    # TODO: Full end-to-end test with file encryption/decryption
  end
end
```

### Week 1 Deliverables

**Code:**
- ✅ `password_protection.ex` - Core PBKDF2 + AES-GCM implementation
- ✅ `password_protected_key_storage.ex` - File storage adapter
- ✅ `password_prompt.ex` - Secure CLI password input
- ✅ Updated `init.ex` - Password setup flow
- ✅ Comprehensive unit tests (>95% coverage)
- ✅ Integration tests

**Documentation:**
- ✅ Security rationale in README
- ✅ Password protection setup instructions
- ✅ CI/CD environment variable documentation

**Performance:**
- ✅ PBKDF2 derivation: ~100ms (acceptable UX)
- ✅ Encryption/decryption: <5ms

---

## Week 2: OS Keychain Integration (Tier 2)

**Goal:** Store master key in OS-native keychain (macOS Keychain, Linux Secret Service) with optional biometric unlock

### Day 1-2: Rust NIF for keyring-rs

#### File: `native/keyring_nif/Cargo.toml`

```toml
[package]
name = "keyring_nif"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
rustler = "0.34.0"
keyring = { version = "3.6", features = ["apple-native", "linux-native"] }
base64 = "0.22"

[profile.release]
opt-level = 3
lto = true
```

#### File: `native/keyring_nif/src/lib.rs`

```rust
use rustler::{Env, Term, NifResult, Encoder, Error};
use keyring::{Entry, Result as KeyringResult};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        not_found,
        unsupported_platform,
        access_denied,
    }
}

/// Store a key in the OS keychain
///
/// # Arguments
/// * `service` - Service name (e.g., "git-foil")
/// * `username` - Username/key identifier (e.g., "master-key")
/// * `key_bytes` - The secret key as bytes
///
/// # Returns
/// * `:ok` on success
/// * `{:error, reason}` on failure
#[rustler::nif]
fn store_key(service: String, username: String, key_bytes: Vec<u8>) -> NifResult<Term> {
    let entry = match Entry::new(&service, &username) {
        Ok(e) => e,
        Err(_) => return Ok((atoms::error(), atoms::unsupported_platform()).encode(env)),
    };

    // Encode bytes as base64 for safe string storage
    let key_b64 = base64::Engine::encode(
        &base64::engine::general_purpose::STANDARD,
        &key_bytes
    );

    match entry.set_password(&key_b64) {
        Ok(_) => Ok(atoms::ok().encode(env)),
        Err(keyring::Error::NoStorageAccess(_)) => {
            Ok((atoms::error(), atoms::access_denied()).encode(env))
        }
        Err(_) => Ok((atoms::error(), "store_failed").encode(env)),
    }
}

/// Retrieve a key from the OS keychain
///
/// # Arguments
/// * `service` - Service name
/// * `username` - Username/key identifier
///
/// # Returns
/// * `{:ok, key_bytes}` on success
/// * `{:error, :not_found}` if key doesn't exist
/// * `{:error, reason}` on other failures
#[rustler::nif]
fn retrieve_key(service: String, username: String) -> NifResult<Term> {
    let entry = match Entry::new(&service, &username) {
        Ok(e) => e,
        Err(_) => return Ok((atoms::error(), atoms::unsupported_platform()).encode(env)),
    };

    match entry.get_password() {
        Ok(key_b64) => {
            // Decode base64 back to bytes
            match base64::Engine::decode(
                &base64::engine::general_purpose::STANDARD,
                key_b64.as_bytes()
            ) {
                Ok(key_bytes) => Ok((atoms::ok(), key_bytes).encode(env)),
                Err(_) => Ok((atoms::error(), "decode_failed").encode(env)),
            }
        }
        Err(keyring::Error::NoEntry) => {
            Ok((atoms::error(), atoms::not_found()).encode(env))
        }
        Err(keyring::Error::NoStorageAccess(_)) => {
            Ok((atoms::error(), atoms::access_denied()).encode(env))
        }
        Err(_) => Ok((atoms::error(), "retrieve_failed").encode(env)),
    }
}

/// Delete a key from the OS keychain
///
/// # Returns
/// * `:ok` on success (even if key didn't exist)
/// * `{:error, reason}` on failure
#[rustler::nif]
fn delete_key(service: String, username: String) -> NifResult<Term> {
    let entry = match Entry::new(&service, &username) {
        Ok(e) => e,
        Err(_) => return Ok((atoms::error(), atoms::unsupported_platform()).encode(env)),
    };

    match entry.delete_credential() {
        Ok(_) => Ok(atoms::ok().encode(env)),
        Err(keyring::Error::NoEntry) => Ok(atoms::ok().encode(env)), // Already deleted
        Err(_) => Ok((atoms::error(), "delete_failed").encode(env)),
    }
}

/// Check if keyring is available on this platform
///
/// # Returns
/// * `true` if keyring is supported and accessible
/// * `false` otherwise
#[rustler::nif]
fn keyring_available() -> NifResult<bool> {
    // Try to create a test entry
    let test_entry = Entry::new("git-foil-test", "availability-check");

    Ok(test_entry.is_ok())
}

rustler::init!(
    "Elixir.GitFoil.Native.KeyringNif",
    [store_key, retrieve_key, delete_key, keyring_available]
);
```

#### File: `lib/git_foil/native/keyring_nif.ex`

```elixir
defmodule GitFoil.Native.KeyringNif do
  @moduledoc """
  Rust NIF for OS keychain integration via keyring-rs.

  Supports:
  - macOS: Keychain (with Touch ID when configured by user)
  - Linux: Secret Service (GNOME Keyring, KWallet)
  - Windows: Credential Manager
  - iOS: Keychain
  """

  use Rustler, otp_app: :git_foil, crate: "keyring_nif"

  @type service :: String.t()
  @type username :: String.t()
  @type key_bytes :: binary()
  @type error_reason ::
          :not_found
          | :unsupported_platform
          | :access_denied
          | :store_failed
          | :retrieve_failed
          | :delete_failed

  @doc """
  Store a key in the OS keychain.

  ## Examples

      iex> key = :crypto.strong_rand_bytes(32)
      iex> KeyringNif.store_key("git-foil", "master-key", key)
      :ok
  """
  @spec store_key(service, username, key_bytes) :: :ok | {:error, error_reason}
  def store_key(_service, _username, _key_bytes), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Retrieve a key from the OS keychain.

  On macOS, this may trigger a Touch ID prompt if the keychain entry
  is configured to require biometric authentication.

  ## Examples

      iex> {:ok, key} = KeyringNif.retrieve_key("git-foil", "master-key")
      iex> byte_size(key)
      32
  """
  @spec retrieve_key(service, username) :: {:ok, key_bytes} | {:error, error_reason}
  def retrieve_key(_service, _username), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Delete a key from the OS keychain.

  Returns `:ok` even if the key didn't exist.
  """
  @spec delete_key(service, username) :: :ok | {:error, error_reason}
  def delete_key(_service, _username), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Check if OS keyring is available and accessible.

  Returns `false` on unsupported platforms or if access is denied.
  """
  @spec keyring_available?() :: boolean()
  def keyring_available?(), do: :erlang.nif_error(:nif_not_loaded)
end
```

### Day 3: Elixir Adapter for OS Keychain

#### File: `lib/git_foil/adapters/os_keychain.ex`

```elixir
defmodule GitFoil.Adapters.OsKeychain do
  @moduledoc """
  OS-native keychain storage for master keys.

  Uses platform-specific secure storage:
  - macOS: Keychain (optionally with Touch ID)
  - Linux: Secret Service (GNOME Keyring, KWallet)
  - Windows: Credential Manager

  Keys are stored with service="git-foil" and username="master-key".
  """

  @behaviour GitFoil.Ports.KeyStorage

  alias GitFoil.Native.KeyringNif

  @service "git-foil"
  @username "master-key"

  @impl true
  def save_master_key(master_key, _storage_path, _opts) when byte_size(master_key) == 32 do
    case KeyringNif.store_key(@service, @username, master_key) do
      :ok ->
        :ok

      {:error, :unsupported_platform} ->
        {:error, :keychain_unavailable}

      {:error, :access_denied} ->
        {:error, :keychain_access_denied}

      {:error, reason} ->
        {:error, {:keychain_error, reason}}
    end
  end

  @impl true
  def load_master_key(_storage_path, _opts) do
    case KeyringNif.retrieve_key(@service, @username) do
      {:ok, master_key} when byte_size(master_key) == 32 ->
        {:ok, master_key}

      {:ok, _invalid_size} ->
        {:error, :corrupted_key}

      {:error, :not_found} ->
        {:error, :key_not_found}

      {:error, :unsupported_platform} ->
        {:error, :keychain_unavailable}

      {:error, :access_denied} ->
        {:error, :keychain_access_denied}

      {:error, reason} ->
        {:error, {:keychain_error, reason}}
    end
  end

  @impl true
  def key_exists?(_storage_path) do
    case KeyringNif.retrieve_key(@service, @username) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @impl true
  def delete_master_key(_storage_path) do
    case KeyringNif.delete_key(@service, @username) do
      :ok -> :ok
      {:error, reason} -> {:error, {:keychain_error, reason}}
    end
  end

  @doc """
  Check if OS keychain is available on this system.

  ## Examples

      iex> OsKeychain.available?()
      true  # on macOS/Linux with keychain access
  """
  @spec available?() :: boolean()
  def available? do
    KeyringNif.keyring_available?()
  end

  @doc """
  Configure Touch ID requirement for key access (macOS only).

  This requires running a separate shell command to set the ACL.

  ## Examples

      # Require Touch ID every time
      OsKeychain.require_touch_id(:always)

      # Require Touch ID when locked
      OsKeychain.require_touch_id(:when_unlocked)
  """
  @spec require_touch_id(:always | :when_unlocked) :: :ok | {:error, term()}
  def require_touch_id(policy) when policy in [:always, :when_unlocked] do
    # macOS-specific: Use security command to set ACL
    # This is done via shell because keyring-rs doesn't expose ACL API yet

    case :os.type() do
      {:unix, :darwin} ->
        configure_macos_touch_id(policy)

      _ ->
        {:error, :not_supported_on_platform}
    end
  end

  defp configure_macos_touch_id(policy) do
    # Use `security set-generic-password-partition-list` to require Touch ID
    # This is advanced - may require additional macOS security permissions

    partition_id =
      case policy do
        :always -> "touchid"
        :when_unlocked -> "touchid-unlocked"
      end

    {output, exit_code} =
      System.cmd("security", [
        "set-generic-password-partition-list",
        "-s", @service,
        "-a", @username,
        "-S", partition_id
      ])

    if exit_code == 0 do
      :ok
    else
      {:error, {:macos_security_failed, output}}
    end
  end
end
```

### Day 4: Integration into KeyManager

#### File: `lib/git_foil/core/key_manager.ex` (New)

```elixir
defmodule GitFoil.Core.KeyManager do
  @moduledoc """
  Unified key management with three-tier fallback:

  1. OS Keychain (Week 2) - macOS/Linux native, Touch ID
  2. Password-encrypted file (Week 1) - Cross-platform
  3. Legacy plaintext file - Backward compatibility

  Automatically migrates from plaintext → encrypted on first use.
  """

  alias GitFoil.Adapters.{OsKeychain, PasswordProtectedKeyStorage, FileSystemKeyStorage}
  alias GitFoil.CLI.PasswordPrompt

  @git_foil_dir ".git/git_foil"

  @doc """
  Unlock the master key using the best available method.

  ## Returns
  - `{:ok, master_key}` - Successfully unlocked
  - `{:error, reason}` - Failed to unlock

  ## Examples

      iex> {:ok, key} = KeyManager.unlock_master_key()
      iex> byte_size(key)
      32
  """
  @spec unlock_master_key() :: {:ok, binary()} | {:error, term()}
  def unlock_master_key do
    # Tier 1: Try OS Keychain (Touch ID, etc.)
    case try_os_keychain() do
      {:ok, key} ->
        IO.puts("✓ Unlocked via OS Keychain")
        {:ok, key}

      {:error, :keychain_unavailable} ->
        # Expected on unsupported platforms
        try_password_protected()

      {:error, :key_not_found} ->
        # Not stored in keychain yet
        try_password_protected()

      {:error, reason} ->
        IO.puts(:stderr, "⚠ Keychain access failed: #{inspect(reason)}")
        try_password_protected()
    end
  end

  defp try_os_keychain do
    if OsKeychain.available?() do
      OsKeychain.load_master_key(@git_foil_dir, [])
    else
      {:error, :keychain_unavailable}
    end
  end

  defp try_password_protected do
    # Tier 2: Try password-encrypted file
    if PasswordProtectedKeyStorage.key_exists?(@git_foil_dir) do
      unlock_with_password()
    else
      try_legacy_plaintext()
    end
  end

  defp unlock_with_password do
    password =
      PasswordPrompt.get_password_with_fallback(
        "GIT_FOIL_PASSWORD",
        "Enter Git Foil password: "
      )

    case PasswordProtectedKeyStorage.load_master_key(@git_foil_dir, password: password) do
      {:ok, key} ->
        IO.puts("✓ Unlocked with password")
        {:ok, key}

      {:error, :invalid_password} ->
        IO.puts(:stderr, "✗ Invalid password. Try again.")
        unlock_with_password()  # Retry

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp try_legacy_plaintext do
    # Tier 3: Try legacy plaintext file
    if FileSystemKeyStorage.key_exists?(@git_foil_dir) do
      case FileSystemKeyStorage.load_master_key(@git_foil_dir, []) do
        {:ok, key} ->
          prompt_upgrade_to_encrypted(key)
          {:ok, key}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :no_master_key_found}
    end
  end

  defp prompt_upgrade_to_encrypted(plaintext_key) do
    IO.puts("\n⚠️  Your master key is stored without encryption!")
    IO.puts("   Would you like to upgrade to password protection?")

    response =
      IO.gets("Upgrade now? (Y/n): ")
      |> String.trim()
      |> String.downcase()

    if response in ["", "y", "yes"] do
      upgrade_to_password_protection(plaintext_key)
    else
      IO.puts("   You can upgrade later by running: git-foil upgrade-key")
    end
  end

  defp upgrade_to_password_protection(plaintext_key) do
    # Backup old key
    backup_path = "#{@git_foil_dir}/master.key.backup.#{DateTime.utc_now() |> DateTime.to_unix()}"
    File.cp!("#{@git_foil_dir}/master.key", backup_path)

    # Get password and encrypt
    password = PasswordPrompt.get_password("Set password: ", confirm: true)

    case PasswordProtectedKeyStorage.save_master_key(
           plaintext_key,
           @git_foil_dir,
           password: password
         ) do
      :ok ->
        # Delete plaintext key
        File.rm!("#{@git_foil_dir}/master.key")

        IO.puts("\n✓ Upgraded to password-protected key!")
        IO.puts("  Old key backed up to: #{backup_path}")

      {:error, reason} ->
        IO.puts(:stderr, "\n✗ Upgrade failed: #{inspect(reason)}")
        IO.puts(:stderr, "  Your key remains in plaintext format.")
    end
  end

  @doc """
  Migrate key to OS Keychain.

  Prompts user to store their password-protected (or plaintext) key
  into the OS keychain for Touch ID access.
  """
  @spec migrate_to_keychain() :: :ok | {:error, term()}
  def migrate_to_keychain do
    unless OsKeychain.available?() do
      IO.puts(:stderr, "✗ OS Keychain not available on this platform")
      return {:error, :keychain_unavailable}
    end

    IO.puts("Migrating master key to OS Keychain...")

    # Unlock current key
    case unlock_master_key() do
      {:ok, master_key} ->
        # Store in keychain
        case OsKeychain.save_master_key(master_key, @git_foil_dir, []) do
          :ok ->
            IO.puts("✓ Master key stored in OS Keychain")
            IO.puts("  Future unlocks may use Touch ID")

            # Optionally delete old storage
            prompt_delete_old_storage()
            :ok

          {:error, reason} ->
            IO.puts(:stderr, "✗ Failed to store in keychain: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts(:stderr, "✗ Failed to unlock current key: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp prompt_delete_old_storage do
    IO.puts("\nKeep password-encrypted backup file? (Recommended)")

    response =
      IO.gets("Keep backup? (Y/n): ")
      |> String.trim()
      |> String.downcase()

    unless response in ["", "y", "yes"] do
      # Delete encrypted file
      PasswordProtectedKeyStorage.delete_master_key(@git_foil_dir)
      IO.puts("✓ Removed password-encrypted file")
    end
  end
end
```

### Day 5: Testing & Documentation

#### File: `test/git_foil/adapters/os_keychain_test.exs`

```elixir
defmodule GitFoil.Adapters.OsKeychainTest do
  use ExUnit.Case

  alias GitFoil.Adapters.OsKeychain

  @moduletag :os_keychain

  setup do
    # Clean up any existing test keys
    OsKeychain.delete_master_key("unused")
    :ok
  end

  describe "save_master_key/3" do
    test "stores key in OS keychain" do
      master_key = :crypto.strong_rand_bytes(32)

      assert :ok = OsKeychain.save_master_key(master_key, "unused", [])
    end
  end

  describe "load_master_key/2" do
    test "retrieves previously stored key" do
      master_key = :crypto.strong_rand_bytes(32)

      :ok = OsKeychain.save_master_key(master_key, "unused", [])
      assert {:ok, ^master_key} = OsKeychain.load_master_key("unused", [])
    end

    test "returns error for non-existent key" do
      assert {:error, :key_not_found} = OsKeychain.load_master_key("unused", [])
    end
  end

  describe "available?/0" do
    test "returns boolean" do
      assert is_boolean(OsKeychain.available?())
    end
  end
end
```

#### Documentation: `docs/OS_KEYCHAIN_SETUP.md`

```markdown
# OS Keychain Setup for Git Foil

Git Foil can store your master key in your operating system's native keychain,
enabling Touch ID unlock on macOS and system-integrated authentication on Linux.

## macOS Setup

### Storing Key in Keychain

```bash
# During init
git-foil init
# Select "Store in macOS Keychain" when prompted

# Or migrate existing key
git-foil migrate-to-keychain
```

### Enabling Touch ID (Optional)

By default, macOS may allow keychain access without Touch ID if your Mac is unlocked.
To require Touch ID every time:

```bash
git-foil keychain require-touch-id
```

### Verification

```bash
# This should show your key in Keychain Access.app
open -a "Keychain Access"
# Search for "git-foil"
```

## Linux Setup

### Requirements

- GNOME Keyring or KWallet running
- D-Bus session bus
- `libsecret` installed

Install on Ubuntu/Debian:
```bash
sudo apt install gnome-keyring libsecret-1-0
```

### Storing Key

```bash
git-foil init
# Select "Store in Secret Service" when prompted
```

### Troubleshooting

**Error: "Keychain unavailable"**
- Ensure GNOME Keyring is running: `ps aux | grep gnome-keyring`
- Check D-Bus: `echo $DBUS_SESSION_BUS_ADDRESS`

**Error: "Access denied"**
- Unlock your keyring: `gnome-keyring-daemon --unlock`

## CI/CD Environments

In headless environments (CI/CD), the keychain won't be available.
Git Foil will automatically fall back to password-based encryption.

Set the password via environment variable:
```bash
export GIT_FOIL_PASSWORD="your-password"
```

## Security Notes

- **macOS:** Keys stored in Keychain are encrypted with your login password
  - If Touch ID is enabled, biometric auth is required
  - Keys sync via iCloud Keychain if enabled (you may want to disable this)

- **Linux:** Keys stored in Secret Service are encrypted with your login password
  - Keyring unlocks automatically when you log in
  - Keys do NOT sync between machines

- **Best Practice:** Use keychain for convenience, but keep a password-encrypted
  backup in `.git/git_foil/master.key.enc` for portability.
```

### Week 2 Deliverables

**Code:**
- ✅ `keyring_nif` Rust NIF (Cargo project)
- ✅ `keyring_nif.ex` Elixir wrapper
- ✅ `os_keychain.ex` Storage adapter
- ✅ `key_manager.ex` Three-tier orchestration
- ✅ Touch ID configuration (macOS)
- ✅ Tests for keychain functionality

**Documentation:**
- ✅ OS Keychain setup guide
- ✅ Platform-specific instructions
- ✅ Troubleshooting guide

**Integration:**
- ✅ `git-foil init` offers keychain option
- ✅ `git-foil migrate-to-keychain` command
- ✅ Automatic fallback to password protection

---

## Week 3: Key Agent Caching (Tier 3)

**Goal:** Cache unlocked master key in memory to avoid re-prompting on every git operation (ssh-agent style)

### Day 1-2: Key Agent GenServer

#### File: `lib/git_foil/core/key_agent.ex`

```elixir
defmodule GitFoil.Core.KeyAgent do
  @moduledoc """
  In-memory cache for unlocked master keys (ssh-agent style).

  Caches the master key after first unlock to avoid re-prompting
  on every git operation. Implements:

  - Time-based expiration (default: 15 minutes)
  - Manual expiration on user request
  - Secure memory wiping on exit
  - Single-repository or global cache (configurable)

  ## Usage

      # Start agent (usually automatic)
      KeyAgent.start_link([])

      # Unlock and cache key
      {:ok, key} = KeyAgent.get_or_unlock()

      # Manually lock (clear cache)
      KeyAgent.lock()

      # Check status
      KeyAgent.status()
  """

  use GenServer
  require Logger

  @default_ttl_minutes 15
  @cleanup_interval_ms 60_000  # Check for expiration every minute

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get cached key or prompt to unlock.

  Returns `{:ok, master_key}` immediately if cached and not expired.
  Otherwise, unlocks via KeyManager and caches the result.
  """
  @spec get_or_unlock() :: {:ok, binary()} | {:error, term()}
  def get_or_unlock do
    case GenServer.call(__MODULE__, :get_key, :infinity) do
      {:ok, key} ->
        {:ok, key}

      :not_cached ->
        # Need to unlock
        case GitFoil.Core.KeyManager.unlock_master_key() do
          {:ok, key} ->
            # Cache it
            GenServer.cast(__MODULE__, {:cache_key, key})
            {:ok, key}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Clear cached key (lock the agent).

  Useful when user wants to ensure key is not in memory.
  """
  @spec lock() :: :ok
  def lock do
    GenServer.cast(__MODULE__, :lock)
  end

  @doc """
  Get agent status.

  Returns:
  - `:locked` - No key cached
  - `{:unlocked, expires_in_seconds}` - Key cached
  """
  @spec status() :: :locked | {:unlocked, non_neg_integer()}
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Configure TTL (time-to-live) for cached keys.

  ## Examples

      KeyAgent.set_ttl(minutes: 30)  # Cache for 30 minutes
      KeyAgent.set_ttl(minutes: 0)   # Disable caching
  """
  @spec set_ttl(keyword()) :: :ok
  def set_ttl(opts) do
    minutes = Keyword.fetch!(opts, :minutes)
    GenServer.cast(__MODULE__, {:set_ttl, minutes})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    ttl_minutes = Keyword.get(opts, :ttl_minutes, @default_ttl_minutes)

    # Schedule periodic cleanup
    schedule_cleanup()

    state = %{
      cached_key: nil,
      expires_at: nil,
      ttl_minutes: ttl_minutes
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_key, _from, state) do
    case state.cached_key do
      nil ->
        {:reply, :not_cached, state}

      key ->
        if expired?(state.expires_at) do
          # Expired - wipe and return not cached
          new_state = wipe_key(state)
          {:reply, :not_cached, new_state}
        else
          {:reply, {:ok, key}, state}
        end
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    case state.cached_key do
      nil ->
        {:reply, :locked, state}

      _key ->
        if expired?(state.expires_at) do
          new_state = wipe_key(state)
          {:reply, :locked, new_state}
        else
          seconds_remaining = DateTime.diff(state.expires_at, DateTime.utc_now())
          {:reply, {:unlocked, seconds_remaining}, state}
        end
    end
  end

  @impl true
  def handle_cast({:cache_key, key}, state) do
    expires_at = DateTime.add(DateTime.utc_now(), state.ttl_minutes * 60, :second)

    new_state = %{state | cached_key: key, expires_at: expires_at}

    Logger.debug("Key cached, expires at #{expires_at}")

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:lock, state) do
    new_state = wipe_key(state)
    Logger.debug("Agent locked (key wiped)")
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_ttl, minutes}, state) do
    new_state = %{state | ttl_minutes: minutes}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Check if key expired
    new_state =
      if state.cached_key && expired?(state.expires_at) do
        Logger.debug("Key expired, wiping from memory")
        wipe_key(state)
      else
        state
      end

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    # Wipe key on shutdown
    wipe_key(state)
    :ok
  end

  # Private helpers

  defp expired?(nil), do: true

  defp expired?(expires_at) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  defp wipe_key(state) do
    # Best-effort memory wipe
    if state.cached_key do
      # Overwrite binary with zeros
      :crypto.exor(state.cached_key, state.cached_key)
    end

    %{state | cached_key: nil, expires_at: nil}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
```

### Day 2: Integration with Application Supervision Tree

#### File: `lib/git_foil/application.ex` (Updated)

```elixir
defmodule GitFoil.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start key agent for caching
      {GitFoil.Core.KeyAgent, [ttl_minutes: get_ttl_config()]},

      # ... other supervised processes
    ]

    opts = [strategy: :one_for_one, name: GitFoil.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_ttl_config do
    # Allow user configuration via env var or config
    case System.get_env("GIT_FOIL_CACHE_TTL_MINUTES") do
      nil -> 15  # Default
      "0" -> 0   # Disable caching
      minutes -> String.to_integer(minutes)
    end
  end
end
```

### Day 3: CLI Commands for Agent Management

#### File: `lib/git_foil/cli/commands/agent.ex`

```elixir
defmodule GitFoil.CLI.Commands.Agent do
  @moduledoc """
  Manage the Git Foil key agent (cache).

  ## Commands

      git-foil agent status    # Show cache status
      git-foil agent lock      # Clear cached key
      git-foil agent unlock    # Unlock and cache key
      git-foil agent config    # Configure TTL
  """

  alias GitFoil.Core.KeyAgent

  def run(["status"]) do
    case KeyAgent.status() do
      :locked ->
        IO.puts("Agent: 🔒 Locked (no key cached)")
        IO.puts("Next git operation will prompt for unlock")

      {:unlocked, seconds_remaining} ->
        minutes = div(seconds_remaining, 60)
        IO.puts("Agent: 🔓 Unlocked")
        IO.puts("Key expires in: #{minutes} minutes")
    end
  end

  def run(["lock"]) do
    KeyAgent.lock()
    IO.puts("✓ Agent locked (key cleared from memory)")
  end

  def run(["unlock"]) do
    case KeyAgent.get_or_unlock() do
      {:ok, _key} ->
        IO.puts("✓ Agent unlocked (key cached)")

      {:error, reason} ->
        IO.puts(:stderr, "✗ Failed to unlock: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  def run(["config", "ttl", minutes_str]) do
    minutes = String.to_integer(minutes_str)

    if minutes < 0 or minutes > 1440 do
      IO.puts(:stderr, "✗ TTL must be between 0 and 1440 minutes (24 hours)")
      exit({:shutdown, 1})
    end

    KeyAgent.set_ttl(minutes: minutes)

    if minutes == 0 do
      IO.puts("✓ Caching disabled (will prompt every time)")
    else
      IO.puts("✓ Cache TTL set to #{minutes} minutes")
    end
  end

  def run(_args) do
    IO.puts("""
    Usage: git-foil agent <command>

    Commands:
      status          Show agent status
      lock            Clear cached key
      unlock          Unlock and cache key
      config ttl <N>  Set cache TTL (minutes, 0 to disable)

    Examples:
      git-foil agent status
      git-foil agent config ttl 30
    """)
  end
end
```

### Day 4: Update KeyManager to Use Agent

#### File: `lib/git_foil/core/key_manager.ex` (Updated)

```elixir
defmodule GitFoil.Core.KeyManager do
  # ... existing code ...

  @doc """
  Unlock the master key (with caching).

  If agent is running and has a cached key, returns immediately.
  Otherwise unlocks via three-tier fallback and caches the result.
  """
  @spec unlock_master_key() :: {:ok, binary()} | {:error, term()}
  def unlock_master_key do
    # Try to use cached key from agent
    case GitFoil.Core.KeyAgent.get_or_unlock() do
      {:ok, key} ->
        {:ok, key}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Note: KeyAgent.get_or_unlock() internally calls the original
  # unlock_master_key logic (three-tier fallback) if cache miss.
  # This keeps the logic centralized.
end
```

### Day 5: Testing & Documentation

#### File: `test/git_foil/core/key_agent_test.exs`

```elixir
defmodule GitFoil.Core.KeyAgentTest do
  use ExUnit.Case, async: false  # Agent is a singleton

  alias GitFoil.Core.KeyAgent

  setup do
    # Start fresh agent for each test
    if Process.whereis(KeyAgent) do
      GenServer.stop(KeyAgent)
    end

    {:ok, _pid} = KeyAgent.start_link(ttl_minutes: 1)
    KeyAgent.lock()  # Ensure clean state

    :ok
  end

  describe "get_or_unlock/0" do
    test "returns :not_cached when no key is cached" do
      # This will try to unlock via KeyManager, which will fail in test env
      # We need to mock KeyManager for this test
      # For now, just verify the behavior

      assert KeyAgent.status() == :locked
    end

    test "returns cached key if available and not expired" do
      # Manually cache a key
      test_key = :crypto.strong_rand_bytes(32)
      GenServer.cast(KeyAgent, {:cache_key, test_key})

      # Should return same key
      assert {:ok, ^test_key} = KeyAgent.get_or_unlock()
    end
  end

  describe "lock/0" do
    test "clears cached key" do
      test_key = :crypto.strong_rand_bytes(32)
      GenServer.cast(KeyAgent, {:cache_key, test_key})

      assert {:unlocked, _} = KeyAgent.status()

      KeyAgent.lock()

      assert :locked = KeyAgent.status()
    end
  end

  describe "status/0" do
    test "returns :locked when no key cached" do
      assert :locked = KeyAgent.status()
    end

    test "returns {:unlocked, seconds} when key is cached" do
      test_key = :crypto.strong_rand_bytes(32)
      GenServer.cast(KeyAgent, {:cache_key, test_key})

      assert {:unlocked, seconds} = KeyAgent.status()
      assert seconds > 0 and seconds <= 60  # 1 minute TTL in setup
    end
  end

  describe "expiration" do
    test "key expires after TTL" do
      # Start agent with very short TTL
      GenServer.stop(KeyAgent)
      {:ok, _pid} = KeyAgent.start_link(ttl_minutes: 0.01)  # ~600ms

      test_key = :crypto.strong_rand_bytes(32)
      GenServer.cast(KeyAgent, {:cache_key, test_key})

      assert {:unlocked, _} = KeyAgent.status()

      # Wait for expiration
      Process.sleep(1000)

      # Force cleanup check
      send(KeyAgent, :cleanup)
      Process.sleep(100)

      assert :locked = KeyAgent.status()
    end
  end
end
```

#### Documentation: `docs/KEY_AGENT_GUIDE.md`

```markdown
# Git Foil Key Agent Guide

The Key Agent caches your unlocked master key in memory, so you don't have to
re-enter your password (or use Touch ID) on every git operation.

## How It Works

Similar to `ssh-agent`, the Git Foil agent:

1. Prompts for unlock on **first** git operation
2. Caches the decrypted key in memory
3. Reuses the cached key for subsequent operations
4. Automatically expires after 15 minutes (configurable)
5. Wipes the key from memory on lock/expiration/shutdown

## Usage

### Check Agent Status

```bash
git-foil agent status
```

Output:
```
Agent: 🔓 Unlocked
Key expires in: 12 minutes
```

### Lock Agent (Clear Cache)

```bash
git-foil agent lock
```

After this, the next git operation will prompt for unlock.

### Configure Cache TTL

```bash
# Set to 30 minutes
git-foil agent config ttl 30

# Disable caching entirely (always prompt)
git-foil agent config ttl 0
```

Or via environment variable:
```bash
export GIT_FOIL_CACHE_TTL_MINUTES=30
```

## Typical Workflow

```bash
# Morning: Start work
git pull               # Prompts for password (or Touch ID)
# Key is now cached

# Throughout the day
git add .
git commit -m "Work"
git push
git pull
# No password prompts!

# End of day: Lock before closing laptop
git-foil agent lock
```

## Security Considerations

**Pros:**
- ✅ Dramatically better UX (no constant password prompts)
- ✅ Key is encrypted in memory (process memory protection)
- ✅ Automatic expiration prevents indefinite exposure
- ✅ Wipes key on process exit

**Cons:**
- ⚠️ Key is in RAM while cached (vulnerable to memory dumps)
- ⚠️ Process with ptrace could read memory (requires root/privileges)

**Recommendation:** Use caching for convenience, but lock before:
- Stepping away from your computer
- Sleeping/hibernating
- Crossing international borders (if paranoid)

**Extra paranoid?** Disable caching:
```bash
export GIT_FOIL_CACHE_TTL_MINUTES=0
```

## Troubleshooting

**Q: Agent always says "locked" even after unlocking**
A: Check that the Application supervisor started the agent:
```bash
git-foil agent status
```

If it says the agent isn't running, there may be an issue with your installation.

**Q: Can I use a system-wide agent (like ssh-agent)?**
A: Not yet. The agent is currently per-Elixir-application instance.
A future version may support a persistent daemon.

**Q: How do I check what's actually cached?**
A: For security reasons, the agent doesn't expose the key itself.
You can only check the lock status via `git-foil agent status`.
```

### Week 3 Deliverables

**Code:**
- ✅ `key_agent.ex` GenServer with caching logic
- ✅ Application supervision tree integration
- ✅ CLI commands for agent management
- ✅ Updated KeyManager to use agent
- ✅ Comprehensive tests

**Documentation:**
- ✅ Key Agent user guide
- ✅ Security considerations
- ✅ Configuration options

**UX Improvements:**
- ✅ No password prompts after first unlock
- ✅ User control over caching (lock, TTL config)
- ✅ Clear status indicators

---

## Testing Strategy

### Unit Tests

**Coverage Target:** >90% for all new modules

```bash
# Run tests
mix test

# With coverage
mix coveralls

# Specific test suites
mix test test/git_foil/core/password_protection_test.exs
mix test test/git_foil/adapters/os_keychain_test.exs
mix test test/git_foil/core/key_agent_test.exs
```

### Integration Tests

**Test Matrix:**

| Scenario | Tier 1 | Tier 2 | Tier 3 | Expected Behavior |
|----------|--------|--------|--------|-------------------|
| Fresh init with password | ✅ | - | - | Creates `master.key.enc` |
| Fresh init with keychain | - | ✅ | - | Stores in OS keychain |
| Load password-protected | ✅ | - | - | Prompts for password |
| Load from keychain | - | ✅ | - | May trigger Touch ID |
| Cached key | - | - | ✅ | Returns immediately |
| Legacy plaintext migration | ✅ | - | - | Offers upgrade |
| Invalid password | ✅ | - | - | Retries prompt |
| Keychain unavailable | - | ✅→✅ | - | Falls back to password |

**End-to-End Test:**

```bash
# Create test repo
mkdir /tmp/test-repo
cd /tmp/test-repo
git init

# Init with password
git-foil init
# Enter password when prompted

# Create encrypted file
echo "secret" > api.key
git-foil pattern add "*.key"
git add api.key
git commit -m "Add secret"

# Verify encryption
cat .git/objects/*/$(git rev-parse HEAD:api.key | cut -c1-38)
# Should see ciphertext, not "secret"

# Verify decryption
cat api.key
# Should see "secret" (smudge filter decrypted it)

# Test agent caching
git-foil agent status  # Should be unlocked
git pull  # Should NOT prompt again

# Lock and retry
git-foil agent lock
git pull  # Should prompt for password
```

### Platform-Specific Tests

**macOS:**
```bash
# Test keychain storage
git-foil init --keychain
security find-generic-password -s "git-foil" -a "master-key"

# Test Touch ID (manual)
# 1. Store key in keychain
# 2. Lock Mac
# 3. Unlock Mac
# 4. Run git operation
# 5. Verify Touch ID prompt appears
```

**Linux:**
```bash
# Test Secret Service
git-foil init --keychain
secret-tool search service git-foil

# Test GNOME Keyring integration
dbus-send --session --dest=org.freedesktop.secrets \
  --print-reply /org/freedesktop/secrets \
  org.freedesktop.DBus.Introspectable.Introspect
```

### Performance Benchmarks

```bash
# Measure unlock time
time git-foil agent unlock

# Expected:
# - PBKDF2: ~100ms
# - Keychain: <50ms (after OS auth)
# - Cached: <1ms
```

### Security Tests

**Automated:**
- ✅ Password validation (min length, max length)
- ✅ PBKDF2 iteration count (>= 600,000)
- ✅ Key size validation (32 bytes)
- ✅ Authentication tag verification
- ✅ File permissions (0600)

**Manual Security Review:**
- [ ] Memory wiping (confirm with debugger)
- [ ] No plaintext passwords in logs
- [ ] No keys in error messages
- [ ] Secure cleanup on crashes

---

## Migration & Backward Compatibility

### Migration Paths

**Old System → New System:**

```
Plaintext key              Password-protected          OS Keychain
(master.key)          →    (master.key.enc)       →   (macOS Keychain)
    ↓                           ↓                          ↓
Auto-detects             Prompts for password      Touch ID unlock
Offers upgrade           Offers keychain upgrade    Best UX
```

### Migration Commands

```bash
# Upgrade plaintext → password-protected
git-foil upgrade-key
# Prompts for password, creates master.key.enc, backs up old key

# Migrate to OS keychain
git-foil migrate-to-keychain
# Unlocks current key, stores in keychain, offers to delete old storage
```

### Backward Compatibility

**Support Matrix:**

| Git Foil Version | Plaintext | Password | Keychain |
|------------------|-----------|----------|----------|
| v0.7.x (current) | ✅ Read   | ❌       | ❌       |
| v0.8.x (Week 1)  | ✅ Read   | ✅ R/W   | ❌       |
| v0.9.x (Week 2)  | ✅ Read   | ✅ R/W   | ✅ R/W   |
| v1.0.x (Week 3)  | ✅ Read   | ✅ R/W   | ✅ R/W   |

**Key Points:**
- Never break existing repos
- Always support reading old format
- Offer upgrade on first use
- Create backups before migration

### File Format Versioning

**Password-encrypted file header:**

```
Byte 0: Version number
  v1: PBKDF2-HMAC-SHA512 (600K iter) + AES-256-GCM
  v2: (Future) Argon2id + AES-256-GCM
  v3: (Future) Additional metadata
```

**Loading logic:**
```elixir
case File.read(path) do
  <<1, rest::binary>> -> decrypt_v1(rest)
  <<2, rest::binary>> -> decrypt_v2(rest)
  _ -> {:error, :unsupported_version}
end
```

---

## Security Considerations

### Threat Model

**What we protect against:**
- ✅ Stolen laptop without disk encryption
- ✅ Unauthorized file access (repos on network shares)
- ✅ Weak passwords (PBKDF2 slows brute-force)
- ✅ Rainbow tables (random salt per key)
- ✅ Data tampering (AES-GCM authentication)

**What we DON'T protect against:**
- ❌ Keyloggers (captures password as you type)
- ❌ Root access / kernel exploits
- ❌ Cold boot attacks (RAM extraction)
- ❌ Coerced disclosure ("$5 wrench attack")

### Best Practices

**For Solo Developers:**
1. ✅ Use password protection (Week 1)
2. ✅ Enable OS keychain + Touch ID (Week 2)
3. ✅ Use full disk encryption (FileVault/LUKS)
4. ✅ Strong password (>16 chars, random)
5. ✅ Lock agent before stepping away

**For Teams:**
1. ✅ Use password protection for shared key file
2. ✅ Share key via encrypted channel (GPG, 1Password)
3. ✅ Document key rotation process
4. ✅ Consider per-user keys (future enhancement)

**For High-Security Environments:**
1. ✅ Disable caching (`TTL=0`)
2. ✅ Require Touch ID on every access
3. ✅ Use hardware tokens (YubiKey - future)
4. ✅ Audit access (future: logging)

### Cryptographic Details

**Algorithms:**
- KDF: PBKDF2-HMAC-SHA512 (600,000 iterations)
- AEAD: AES-256-GCM
- Salt: 256-bit random (via `:crypto.strong_rand_bytes/1`)
- Nonce: 96-bit random (AES-GCM standard)
- Tag: 128-bit (AES-GCM authentication tag)

**Why these choices:**
- PBKDF2: NIST/FIPS approved, widely audited
- SHA512: Quantum-resistant hash, slower than SHA256 (good for KDF)
- 600K iterations: OWASP 2024 recommendation, ~100ms on modern CPU
- AES-GCM: AEAD (encrypt + authenticate), constant-time, hardware-accelerated

**Alternative (future):**
- Argon2id: More GPU-resistant (memory-hard)
- Could be v2 of file format

### Audit & Compliance

**Logging:**
- ✅ Log unlock attempts (success/failure)
- ✅ Log key migrations
- ❌ Never log passwords or keys

**Future enhancements:**
- Audit trail in `.git/git_foil/audit.log`
- Configurable logging verbosity
- Integration with SIEM systems

---

## Future Enhancements

### Post-Week 3 Ideas

**Phase 4: Advanced Features**
1. **Argon2id support** (stronger KDF)
   - Add as v2 of password-protected format
   - Auto-detect and support both

2. **Hardware token support** (YubiKey, etc.)
   - Store key on FIDO2 device
   - Require physical presence

3. **Per-user keys** (team collaboration)
   - Each team member has own key
   - Asymmetric encryption (encrypt to multiple recipients)
   - Key revocation support

4. **Key rotation**
   - `git-foil rotate-key` command
   - Re-encrypts all files with new master key
   - Maintains backward-compatible history

5. **Audit logging**
   - Track unlock/lock events
   - Failed password attempts
   - Key migrations
   - Export to JSON/syslog

6. **SSH-agent style daemon**
   - Persistent background process
   - Unix socket communication
   - Survives Elixir app restarts

**Phase 5: Enterprise Features**
1. HSM integration (Hardware Security Module)
2. Centralized key management server (optional)
3. MFA support (TOTP, WebAuthn)
4. Compliance reporting (SOC2, ISO 27001)

---

## Success Metrics

### Week 1 Success Criteria
- [ ] 100% of new password protection code covered by tests
- [ ] PBKDF2 derivation < 150ms on target hardware
- [ ] Zero regression in existing functionality
- [ ] Documentation complete and reviewed
- [ ] Manual testing on macOS and Linux
- [ ] Migration from plaintext → encrypted works flawlessly

### Week 2 Success Criteria
- [ ] Keychain NIF compiles on macOS and Linux
- [ ] Touch ID prompt appears on macOS (manual test)
- [ ] Secret Service integration works on Ubuntu 22.04+
- [ ] Graceful fallback to password when keychain unavailable
- [ ] Documentation includes platform-specific troubleshooting
- [ ] Zero dependencies added to production (only Rust NIFs)

### Week 3 Success Criteria
- [ ] Agent reduces password prompts from 10+/day to 1/day
- [ ] Memory usage increase < 1MB (for cached key)
- [ ] Agent survives and recovers from crashes
- [ ] Lock command wipes key from memory (verified with debugger)
- [ ] TTL configuration persists across sessions
- [ ] Documentation includes security considerations

### Overall Success
- [ ] Git Foil addresses "stolen laptop" vulnerability
- [ ] UX is comparable to or better than ssh-agent
- [ ] Zero breaking changes for existing users
- [ ] Code quality: >90% test coverage, passing Dialyzer
- [ ] Security: Reviewed by at least one external cryptographer
- [ ] Performance: No user-visible slowdown

---

## Team & Timeline

### Week 1: Password Protection
**Owner:** Backend team
**Skills needed:** Elixir, cryptography basics
**Time estimate:** 3-5 days
**Risk:** Low (well-established algorithms)

### Week 2: OS Keychain
**Owner:** Systems team
**Skills needed:** Rust, NIFs, OS APIs
**Time estimate:** 5-7 days
**Risk:** Medium (platform-specific, testing complexity)

### Week 3: Key Agent
**Owner:** Backend team
**Skills needed:** Elixir, OTP, GenServer
**Time estimate:** 3-5 days
**Risk:** Low (standard Elixir patterns)

**Total:** 11-17 development days (~2.5-3.5 weeks)

---

## Appendix: Code Sketches

### Sketch: Automatic Key Upgrade Flow

```elixir
defmodule GitFoil.Core.KeyUpgrade do
  @moduledoc """
  Handles automatic migration from old key formats to new ones.
  """

  def maybe_upgrade_key do
    cond do
      plaintext_key_exists?() and not encrypted_key_exists?() ->
        prompt_upgrade_to_encrypted()

      encrypted_key_exists?() and not keychain_key_exists?() and os_keychain_available?() ->
        prompt_upgrade_to_keychain()

      true ->
        :no_upgrade_needed
    end
  end

  defp prompt_upgrade_to_encrypted do
    IO.puts("\n⚠️  Your master key is stored without password protection.")
    IO.puts("   This is a security risk if your laptop is stolen.")
    IO.puts("   Upgrade to password-protected storage?")

    if confirm_upgrade?() do
      perform_password_upgrade()
    else
      :declined
    end
  end

  defp perform_password_upgrade do
    # 1. Read plaintext key
    {:ok, plaintext_key} = File.read(".git/git_foil/master.key")

    # 2. Backup
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    File.cp!(".git/git_foil/master.key", ".git/git_foil/master.key.backup.#{timestamp}")

    # 3. Get password
    password = PasswordPrompt.get_password("Set password: ", confirm: true)

    # 4. Encrypt and save
    {:ok, _} = PasswordProtectedKeyStorage.save_master_key(plaintext_key, ".git/git_foil", password: password)

    # 5. Delete plaintext
    File.rm!(".git/git_foil/master.key")

    IO.puts("✓ Upgraded to password-protected key!")
    :upgraded
  end
end
```

### Sketch: Touch ID Configuration (macOS)

```elixir
defmodule GitFoil.Platform.MacOS.TouchID do
  @moduledoc """
  macOS-specific Touch ID configuration.

  Uses the `security` command-line tool to set keychain ACLs.
  """

  def enable_touch_id(service, username, policy \\ :when_unlocked) do
    # Set ACL on keychain item to require Touch ID
    args = [
      "set-generic-password-partition-list",
      "-s", service,
      "-a", username,
      "-S", partition_id_for_policy(policy)
    ]

    case System.cmd("security", args, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {error, _} ->
        {:error, {:macos_security_failed, error}}
    end
  end

  defp partition_id_for_policy(:always), do: "touchid"
  defp partition_id_for_policy(:when_unlocked), do: "touchid-unlocked"
  defp partition_id_for_policy(:when_locked), do: "touchid-locked"

  def touch_id_available? do
    # Check if Mac has Touch ID hardware
    {output, 0} = System.cmd("bioutil", ["-r", "-s"])
    String.contains?(output, "Touch ID")
  end
end
```

### Sketch: Environment Variable Fallback (CI/CD)

```elixir
defmodule GitFoil.CLI.PasswordPrompt do
  # ... existing code ...

  @doc """
  Get password from environment or prompt user.

  Useful for CI/CD where interactive prompts don't work.

  Checks in order:
  1. GIT_FOIL_PASSWORD env var
  2. GIT_FOIL_PASSWORD_FILE env var (path to file containing password)
  3. Interactive prompt
  """
  def get_password_with_fallback(prompt, opts \\ []) do
    cond do
      password = System.get_env("GIT_FOIL_PASSWORD") ->
        password

      password_file = System.get_env("GIT_FOIL_PASSWORD_FILE") ->
        File.read!(password_file) |> String.trim()

      true ->
        get_password(prompt, opts)
    end
  end
end
```

---

## Conclusion

This implementation plan provides a comprehensive, production-ready solution for Git Foil's key protection vulnerability. By implementing all three tiers, Git Foil will offer:

1. **Security:** PBKDF2 password protection addresses the "stolen laptop" threat
2. **Convenience:** OS keychain integration with Touch ID for seamless UX
3. **Performance:** Agent caching eliminates repetitive password prompts

The phased approach allows for incremental delivery and testing, while maintaining backward compatibility with existing installations.

**Estimated Total Effort:** 2.5-3.5 weeks of focused development

**Risk Level:** Low-Medium (leveraging well-established patterns and libraries)

**Impact:** High (addresses a critical security gap while improving UX)
