defmodule Mix.Tasks.Foil do
  @moduledoc """
  Development runner for git-foil CLI.

  This task runs the git-foil CLI in development mode without building an escript.
  Mix automatically recompiles stale modules, so you always run the latest code.

  ## Usage

      mix foil init
      mix foil configure "*.env"
      mix foil encrypt test.txt
      mix foil --version

  ## Why Not Use Escripts in Development?

  Escripts are for distribution (end users), not development:
  - They require rebuilding after every change
  - They add 2-3 seconds to your iteration loop
  - Mix tasks auto-recompile instantly

  Use this task for development. Build escripts only for testing the final artifact.
  """

  use Mix.Task

  @shortdoc "Run git-foil CLI in development mode (auto-recompiles)"

  @impl Mix.Task
  def run(argv) do
    # Start the application and its dependencies
    # This ensures crypto NIFs and other resources are loaded
    Mix.Task.run("app.start")

    # Run the CLI main function
    GitFoil.CLI.main(argv)
  end
end
