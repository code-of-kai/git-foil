#!/usr/bin/env bash
# Local Development Test Runner
# Bypasses homebrew git-foil wrapper and runs tests directly
#
# NOTE: This script contains hardcoded paths specific to the original developer's machine.
# Other developers should use `mix test` directly or modify paths for their environment.

export PATH="/Users/kaitaylor/.asdf/installs/elixir/1.18.4-otp-28/bin:/Users/kaitaylor/.asdf/installs/erlang/28.1/bin:/usr/bin:/bin"
cd /Users/kaitaylor/Documents/Coding/git-foil
exec /Users/kaitaylor/.asdf/installs/elixir/1.18.4-otp-28/bin/elixir /Users/kaitaylor/.asdf/installs/elixir/1.18.4-otp-28/bin/mix test "$@"
