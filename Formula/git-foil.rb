class GitFoil < Formula
  desc "Quantum-resistant Git encryption CLI"
  homepage "https://github.com/code-of-kai/git-foil"
  url "https://github.com/code-of-kai/git-foil/archive/refs/tags/v1.1.3.tar.gz"
  sha256 "e39ae0db1d82977584dc2afa9d5a89aa681110f57be6739a5f8b0b5c4ad769b6"
  license "MIT"

  depends_on "elixir"
  depends_on "erlang"
  depends_on "rust" => :build

  def install
    ENV["MIX_ENV"] = "prod"

    system "mix", "local.hex", "--force"
    system "mix", "local.rebar", "--force"
    system "mix", "deps.get"

    # A single `mix compile` is sufficient: RustlerLoader `require`s the five
    # NIF modules, so Mix builds their crates (and emits the `.so` files) BEFORE
    # RustlerLoader compiles and embeds those bytes into its .beam. If the embed
    # ever comes up empty, RustlerLoader raises at compile time and fails the
    # build here rather than shipping an escript that exits 75 at runtime.
    # (The old `mix compile <file>` "re-embed" step was a no-op: Mix skips an
    # unchanged source, so it never forced the recompile it was meant to.)
    system "mix", "compile"

    libexec.install "priv"

    # Defense-in-depth: also ship the compiled crates on disk so the wrapper's
    # GIT_FOIL_NIF_DIR points at real `.so` files, not just a `.gitkeep`. The
    # escript embeds them too (primary path); this covers the case where the
    # per-user runtime extraction cache is unavailable.
    (libexec/"priv/native").mkpath
    cp Dir["_build/prod/lib/git_foil/priv/native/*.so"], libexec/"priv/native"

    system "mix", "escript.build"
    libexec.install "git-foil"

    (bin/"git-foil").write <<~EOS
      #!/bin/bash
      # git >= 2.11 uses the long-running `filter.gitfoil.process` (the
      # `filter-process` subcommand), which dlopens the crypto NIFs ONCE at
      # startup and serves every file over one process -- so the concurrent
      # dlopen race below cannot occur there. `filter-process` is a persistent
      # process speaking the pkt-line protocol on stdin/stdout: it must NOT be
      # wrapped in stdin buffering or retried, so it falls through to `exec`.
      #
      # The per-file `clean`/`smudge` path remains as a fallback (old git, or a
      # repo not yet reconfigured). There, many short-lived processes dlopen the
      # same .so files in parallel and macOS dyld occasionally races -- a
      # mmap/unified-buffer-cache page-translation fault in
      # dyld4::Loader::mapSegments -> MachOFile::isMachO, triggered e.g. by
      # `git stash push -u`. That race surfaces two ways, both retryable here:
      #   * exit 138 (128 + SIGBUS/signal 10) -- a hard fault, OR
      #   * exit 75  (EX_TEMPFAIL) -- the soft NIF-load failure git-foil now
      #     reports distinctly so a transient load can be retried (it used to be
      #     an indistinguishable generic exit 1 that aborted git).
      #
      # Retry is safe: clean/smudge are deterministic over their stdin, and the
      # failure occurs during BEAM startup before stdin is read. Stdin is
      # buffered to a private tempfile (mktemp default mode 0600) so each retry
      # sees the same input.

      set -uo pipefail
      # Run under the Erlang this CLI was *built* against -- not the user's
      # ambient asdf/rbenv/kerl shims that happen to be first on PATH. The
      # escript shebang is `#!/usr/bin/env escript`, so without this it picks
      # up whatever escript leads PATH. If that runtime's NIF version is older
      # than the build's, precompiled NIFs (pqclean/Kyber1024) fail their ABI
      # check with {:bad_lib, ...} and `init`/`rekey` crash. Pinning to the
      # brew erlang keeps build-erts == runtime-erts.
      export PATH="#{Formula["erlang"].opt_bin}:$PATH"
      export GIT_FOIL_NIF_DIR="#{libexec}/priv/native"
      BIN="#{libexec}/git-foil"

      case "${1:-}" in
          clean|smudge)
              ;;
          *)
              exec "$BIN" "$@"
              ;;
      esac

      stdin_file=$(mktemp -t gitfoil-stdin.XXXXXX)
      trap 'rm -f "$stdin_file"' EXIT INT TERM
      cat > "$stdin_file"

      rc=0
      for attempt in 1 2 3 4 5; do
          "$BIN" "$@" < "$stdin_file"
          rc=$?
          case "$rc" in
              138|75) ;;        # transient (SIGBUS / EX_TEMPFAIL): retry
              *) break ;;
          esac
          sleep 0.1
      done

      exit "$rc"
    EOS
    (bin/"git-foil").chmod 0o755
  end

  test do
    assert_match "GitFoil version", shell_output("#{bin}/git-foil version")
  end
end
