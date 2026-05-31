defmodule GitFoil.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # MUST be first: stdout is the encrypted blob (clean/smudge) or the pkt-line
    # wire (filter-process). The NIF loads below can log to stdout on failure
    # (e.g. a flapping pqclean_nif), which would be baked into a Git object.
    # Route all logging to stderr before anything can log.
    GitFoil.Logging.redirect_to_stderr()

    _ = GitFoil.Native.RustlerLoader.ensure_loaded()
    _ = GitFoil.Native.PqcleanLoader.ensure_loaded()

    # Start a minimal supervisor (required for OTP application)
    # The actual CLI is invoked directly via mix run in the Homebrew wrapper
    children = []
    opts = [strategy: :one_for_one, name: GitFoil.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
