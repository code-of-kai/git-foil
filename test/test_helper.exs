ExUnit.start()

Path.wildcard(Path.expand("support/**/*.exs", __DIR__))
|> Enum.each(&Code.require_file(&1))
