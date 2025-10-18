defmodule GitFoil.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    _ = GitFoil.Native.RustlerLoader.ensure_loaded()
    _ = GitFoil.Native.PqcleanLoader.ensure_loaded()

    # Start a minimal supervisor (required for OTP application)
    # The actual CLI is invoked directly via mix run in the Homebrew wrapper
    children = []
    opts = [strategy: :one_for_one, name: GitFoil.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
