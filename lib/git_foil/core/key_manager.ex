defmodule GitFoil.Core.KeyManager do
  @moduledoc """
  High-level orchestration for key management and unlocking.

  Provides a unified API for key initialization, storage, and retrieval
  that works with both plaintext and password-protected storage adapters.

  ## Responsibilities
  - Detect which storage adapter is initialized
  - Coordinate password prompting for encrypted storage
  - Derive master encryption keys from keypairs
  - Cache unlocked keys in memory
  - Provide cleanup and security operations

  ## Usage

      # Initialize with password protection
      {:ok, _} = KeyManager.init_with_password("my-secure-password")

      # Unlock existing password-protected storage
      {:ok, master_key} = KeyManager.unlock_with_prompt()

      # Get cached master key (after unlock)
      {:ok, master_key} = KeyManager.get_master_key()

      # Clear cached keys
      :ok = KeyManager.clear_cache()
  """

  alias GitFoil.Adapters.{FileKeyStorage, PasswordProtectedKeyStorage}
  alias GitFoil.Core.Types.{Keypair, EncryptionKey}
  alias GitFoil.CLI.PasswordPrompt

  @process_key_master_key :gitfoil_cached_master_key
  @process_key_keypair :gitfoil_cached_keypair

  # ============================================================================
  # Initialization
  # ============================================================================

  @doc """
  Initializes GitFoil with a new password-protected keypair.

  Generates a new keypair and stores it encrypted with the provided password.

  Returns `{:ok, keypair}` on success.
  """
  @spec init_with_password(String.t()) :: {:ok, Keypair.t()} | {:error, term()}
  def init_with_password(password) when is_binary(password) do
    with {:ok, keypair} <- PasswordProtectedKeyStorage.generate_keypair(),
         :ok <- PasswordProtectedKeyStorage.store_keypair_with_password(keypair, password) do
      # Cache the unlocked keypair
      cache_keypair(keypair)
      {:ok, keypair}
    end
  end

  @doc """
  Initializes GitFoil with plaintext storage (no password).

  Generates a new keypair and stores it unencrypted.

  Returns `{:ok, keypair}` on success.
  """
  @spec init_without_password() :: {:ok, Keypair.t()} | {:error, term()}
  def init_without_password do
    with {:ok, keypair} <- FileKeyStorage.generate_keypair(),
         :ok <- FileKeyStorage.store_keypair(keypair) do
      cache_keypair(keypair)
      {:ok, keypair}
    end
  end

  # ============================================================================
  # Unlocking
  # ============================================================================

  @doc """
  Unlocks GitFoil by prompting for password and deriving master key.

  Detects storage type automatically and prompts if password-protected.
  Returns cached key if already unlocked.

  ## Options
  - `:force_prompt` - Prompt even if key is cached (default: false)

  Returns `{:ok, master_key}` on success.
  """
  @spec unlock_with_prompt(keyword()) :: {:ok, EncryptionKey.t()} | {:error, term()}
  def unlock_with_prompt(opts \\ []) do
    force_prompt = Keyword.get(opts, :force_prompt, false)

    # Check cache first (unless force_prompt)
    if not force_prompt do
      case get_cached_master_key() do
        {:ok, master_key} -> {:ok, master_key}
        :error -> do_unlock_with_prompt()
      end
    else
      do_unlock_with_prompt()
    end
  end

  @doc """
  Unlocks GitFoil with explicit password (no prompt).

  Useful for testing and automation with environment variables.

  Returns `{:ok, master_key}` on success.
  """
  @spec unlock_with_password(String.t()) :: {:ok, EncryptionKey.t()} | {:error, term()}
  def unlock_with_password(password) when is_binary(password) do
    with {:ok, keypair} <-
           PasswordProtectedKeyStorage.retrieve_keypair_with_password(password),
         {:ok, master_key} <- derive_master_key_from_keypair(keypair) do
      cache_keypair(keypair)
      cache_master_key(master_key)
      {:ok, master_key}
    end
  end

  @doc """
  Attempts to unlock without password (plaintext storage).

  Returns `{:ok, master_key}` if plaintext storage is used,
  `{:error, :password_required}` if password-protected.
  """
  @spec unlock_without_password() :: {:ok, EncryptionKey.t()} | {:error, term()}
  def unlock_without_password do
    case FileKeyStorage.retrieve_keypair() do
      {:ok, keypair} ->
        with {:ok, master_key} <- derive_master_key_from_keypair(keypair) do
          cache_keypair(keypair)
          cache_master_key(master_key)
          {:ok, master_key}
        end

      {:error, :not_found} ->
        # Check if password-protected storage exists
        if PasswordProtectedKeyStorage.initialized?() do
          {:error, :password_required}
        else
          {:error, :not_initialized}
        end

      error ->
        error
    end
  end

  # ============================================================================
  # Key Retrieval
  # ============================================================================

  @doc """
  Gets the cached master encryption key.

  Returns `{:ok, master_key}` if unlocked, `{:error, :locked}` otherwise.

  Does NOT prompt for password - use `unlock_with_prompt/0` first.
  """
  @spec get_master_key() :: {:ok, EncryptionKey.t()} | {:error, :locked}
  def get_master_key do
    case get_cached_master_key() do
      {:ok, master_key} -> {:ok, master_key}
      :error -> {:error, :locked}
    end
  end

  @doc """
  Gets the cached keypair.

  Returns `{:ok, keypair}` if unlocked, `{:error, :locked}` otherwise.
  """
  @spec get_keypair() :: {:ok, Keypair.t()} | {:error, :locked}
  def get_keypair do
    case Process.get(@process_key_keypair) do
      nil -> {:error, :locked}
      keypair -> {:ok, keypair}
    end
  end

  # ============================================================================
  # State Management
  # ============================================================================

  @doc """
  Checks if GitFoil has been initialized.

  Returns `{:initialized, :plaintext}` or `{:initialized, :password_protected}`
  or `:not_initialized`.
  """
  @spec initialization_status() ::
          {:initialized, :plaintext | :password_protected} | :not_initialized
  def initialization_status do
    cond do
      FileKeyStorage.initialized?() ->
        {:initialized, :plaintext}

      PasswordProtectedKeyStorage.initialized?() ->
        {:initialized, :password_protected}

      true ->
        :not_initialized
    end
  end

  @doc """
  Checks if keys are currently unlocked (cached in memory).

  Returns `true` if master key is cached, `false` otherwise.
  """
  @spec unlocked?() :: boolean()
  def unlocked? do
    case get_cached_master_key() do
      {:ok, _} -> true
      :error -> false
    end
  end

  @doc """
  Clears all cached keys from memory.

  Good security practice after operations complete.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    Process.delete(@process_key_master_key)
    Process.delete(@process_key_keypair)
    PasswordProtectedKeyStorage.clear_password()
    :ok
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Performs the actual unlock with password prompt
  defp do_unlock_with_prompt do
    case initialization_status() do
      {:initialized, :password_protected} ->
        prompt_and_unlock_password_protected()

      {:initialized, :plaintext} ->
        unlock_without_password()

      :not_initialized ->
        {:error, :not_initialized}
    end
  end

  # Prompts for password and unlocks
  defp prompt_and_unlock_password_protected do
    case PasswordPrompt.get_password_with_fallback("GitFoil password: ") do
      {:ok, password} ->
        case unlock_with_password(password) do
          {:ok, master_key} ->
            {:ok, master_key}

          {:error, :invalid_password} ->
            {:error, :invalid_password}

          error ->
            error
        end

      {:error, reason} ->
        {:error, {:password_prompt_failed, reason}}
    end
  end

  # Derives master encryption key from keypair
  # SHA-512(classical_secret || pq_secret)[0..31]
  defp derive_master_key_from_keypair(%Keypair{} = keypair) do
    combined = keypair.classical_secret <> keypair.pq_secret
    master_key_bytes = :crypto.hash(:sha512, combined) |> binary_part(0, 32)
    master_key = EncryptionKey.new(master_key_bytes)
    {:ok, master_key}
  end

  # Cache management
  defp cache_keypair(keypair), do: Process.put(@process_key_keypair, keypair)
  defp cache_master_key(master_key), do: Process.put(@process_key_master_key, master_key)

  defp get_cached_master_key do
    case Process.get(@process_key_master_key) do
      nil -> :error
      master_key -> {:ok, master_key}
    end
  end
end
