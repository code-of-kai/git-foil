# Compile test support files
Code.require_file("test/support/git_test_helper.ex")
Code.require_file("test/support/test_mocks.ex")

# Add asdf escripts directory to PATH so tests find git-foil-dev
asdf_escripts = Path.expand("~/.asdf/installs/elixir/1.18.4-otp-28/.mix/escripts")
current_path = System.get_env("PATH", "")
System.put_env("PATH", "#{asdf_escripts}:#{current_path}")

ExUnit.start()
