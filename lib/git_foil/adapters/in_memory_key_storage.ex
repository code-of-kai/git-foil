defmodule GitFoil.Adapters.InMemoryKeyStorage do
  @moduledoc """
  In-memory key storage adapter for testing.

  Uses an Agent to store a keypair in memory. Data is lost when the process stops.

  **NOW WITH REAL POST-QUANTUM CRYPTOGRAPHY:**
  Uses pqclean NIF to generate Kyber1024 (ML-KEM-1024) keypairs.

  **For Testing Only** - Do not use in production (keys not persisted).
  """

  @behaviour GitFoil.Ports.KeyStorage

  use Agent

  alias GitFoil.Core.Types.{Keypair, EncryptionKey}

  @doc """
  Start the in-memory key storage agent.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{keypair: nil} end, name: name)
  end

  @impl true
  def generate_keypair do
    # Generate REAL post-quantum keypair using pqclean NIF
    # Kyber1024 provides NIST Level 5 security
    {pq_public, pq_secret} = :pqclean_nif.kyber1024_keypair()

    # For now, use random bytes for classical keypair
    # TODO: Add X25519 classical keypair in future iteration
    classical_public = :crypto.strong_rand_bytes(32)
    classical_secret = :crypto.strong_rand_bytes(32)

    keypair = %Keypair{
      classical_public: classical_public,
      classical_secret: classical_secret,
      pq_public: pq_public,
      pq_secret: pq_secret
    }

    {:ok, keypair}
  end

  @impl true
  def store_keypair(keypair) do
    Agent.update(__MODULE__, fn state ->
      %{state | keypair: keypair}
    end)

    :ok
  end

  @impl true
  def retrieve_keypair do
    case Agent.get(__MODULE__, fn state -> state.keypair end) do
      nil -> {:error, :not_found}
      keypair -> {:ok, keypair}
    end
  end

  @impl true
  def store_file_key(_path, _key) do
    # Not implemented for in-memory storage
    {:error, :not_implemented}
  end

  @impl true
  def retrieve_file_key(_path) do
    {:error, :not_found}
  end

  @impl true
  def delete_file_key(_path) do
    :ok
  end

  # Helper function (not a callback)
  def derive_master_key do
    case retrieve_keypair() do
      {:ok, keypair} ->
        # Deterministic derivation: SHA-512(classical_secret || pq_secret)
        # Take first 32 bytes for 256-bit key
        combined = keypair.classical_secret <> keypair.pq_secret
        master_key_bytes = :crypto.hash(:sha512, combined) |> binary_part(0, 32)
        master_key = EncryptionKey.new(master_key_bytes)
        {:ok, master_key}

      error ->
        error
    end
  end

  # Helper function (not a callback)
  def initialized? do
    case Agent.get(__MODULE__, fn state -> state.keypair end) do
      nil -> false
      _ -> true
    end
  end
end
