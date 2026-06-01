# ADR 004: Distribute git-foil as an OTP release, not an escript

- **Status:** Proposed (deferred behind the v1.1.3 escript fix)
- **Date:** 2026-06-01
- **Deciders:** code-of-kai

## Context

git-foil is a Git clean/smudge filter. Git invokes it constantly and invisibly:
every `git add`, `commit`, `checkout`, and `stash` shells out to the installed
binary to encrypt (`clean`) or decrypt (`smudge`) file contents. The binary's
one job is to load a stack of cryptographic primitives and run bytes through
them deterministically. Five of those primitives are Rust NIFs (AEGIS-256,
Ascon-128a, ChaCha20-Poly1305, Deoxys-II, Schwaemm) plus the pqclean Kyber NIF
for the post-quantum key layer. A NIF is a native shared library (`.so`) that
the BEAM loads with `dlopen` at runtime.

The decision this record concerns is narrow and load-bearing: **what packaging
format do we ship so that those native libraries reliably load on a user's
machine?** Today the answer is an Erlang escript, and that answer is the direct
cause of a recurring class of production failures. The most recent (v1.1.2,
Homebrew keg) shipped a binary that could not load any cipher NIF: every
`clean`/`smudge` failed `on_load` and exited 75, producing empty fail-closed
blobs. The integrity guarantee held, but the tool never actually encrypted.

This is the third failure from the same root. v1.1.0 needed a wrapper retry loop
to survive a macOS `dlopen` race across concurrently-spawned filter processes.
The brew-erlang ABI pin was added because the escript runs under whatever `erl`
leads `PATH`, and a mismatched ERTS fails the pqclean NIF's ABI check. v1.1.2
was an empty-embedding compile-order bug. Each fix was correct; each treated a
symptom of the same underlying mismatch.

## The pattern

The abstract problem is **self-contained native-code distribution**: ship a
runtime, its bytecode, and its native libraries as one unit that loads
identically on every target machine, independent of what else is installed.

Two BEAM packaging primitives sit at opposite ends of this:

- An **escript** is a zip archive of `.beam` modules and an `.app` manifest with
  an `#!/usr/bin/env escript` shebang. It is pure-bytecode by construction. It
  has no `priv/` directory and the BEAM cannot `dlopen` a `.so` out of a zip, so
  native libraries have nowhere to live. It also carries no runtime — it borrows
  whatever `erl`/`escript` is first on `PATH`.

- An **OTP release** is a self-contained directory tree: a private copy of the
  Erlang runtime (ERTS), every compiled application *including its `priv/`
  directory*, and boot scripts. Native libraries sit in
  `lib/<app>-<vsn>/priv/native/` as ordinary files and load through the standard
  `:code.priv_dir/1` path that `use Rustler` already targets. Nothing is
  embedded, extracted, or borrowed from the host.

The pattern git-foil needs is the release. A filter that ships native crypto is
exactly the case OTP releases exist for, and exactly the case escripts exclude.

## Decision

We will distribute git-foil as a **`mix release`** (ERTS bundled via the default
`include_erts: true`), and point the Homebrew formula, the wrapper, and Git's
filter configuration at the release launcher rather than an escript.

Burrito — which wraps a release into a single self-extracting binary with a
cross-compiled bundled runtime — is recorded here as an **optional follow-on**,
warranted only if we later ship prebuilt binaries to users who lack an Elixir
toolchain. It is not required for the Homebrew path, which builds from source on
the user's machine, and it is not currently a dependency (the `build_release.sh`
script names it but nothing wires it in). The plain-release-vs-Burrito choice is
decided separately in ADR-005.

## Rationale

The release primitive is not hypothetical here. The repo already carries a
working `releases()` stanza in `mix.exs` and a `docs/MIX_RELEASE_GUIDE.md` that
documents building `_build/prod/rel/git_foil/bin/git-foil` and states plainly
that the release loads the Rust NIFs and resolves the `UndefinedFunctionError`
that the escript path produces when NIFs fail to load. The native-load behavior
is proven; what is missing is wiring the *distribution* to it and deleting the
escript workaround machinery.

Adopting the release deletes, rather than maintains, four pieces of bespoke code
that exist only to compensate for the escript's inability to carry NIFs:

- `lib/git_foil/native/rustler_loader.ex` bakes the five `.so` files into a
  compile-time module attribute and re-extracts them to a per-user cache at
  startup. This is the exact mechanism that broke in v1.1.2 (the attribute
  embedded an empty map because the module compiled before the crates built).
- `lib/git_foil/native/pqclean_loader.ex` is a second copy of the same staging
  trick for the Kyber NIF, including code-path surgery.
- The wrapper's exit-138/75 retry loop, which buffers stdin to a tempfile and
  retries because many short-lived `clean`/`smudge` processes `dlopen` the same
  cached `.so` concurrently and dyld races.
- The wrapper's `export PATH="brew erlang"` ABI pin, needed only because the
  escript borrows the host runtime. A bundled ERTS makes build-ERTS and
  runtime-ERTS identical by construction.

Alternatives considered:

- **Keep the escript, with the v1.1.3 hardening.** This is the honest
  incumbent, and it now works: v1.1.3 forces the NIF crates to compile before
  `rustler_loader` (via `require`), declares the `.so` files as
  `@external_resource`, and fails the build loudly if the embedding is ever
  empty. The embedding mechanism is legitimate and some projects ship NIF-bearing
  escripts this way. Its weakness is structural, not cosmetic: it keeps all four
  workaround pieces above, it keeps the `dlopen` race surface, and it keeps the
  runtime ABI coupling. It defends a position the ecosystem has already moved off
  of. It is the right *interim* fix and the wrong *terminal* one.
- **Plain `mix release` shipped as a directory tree in `libexec`.** This is the
  decision. Homebrew is comfortable installing a release tree under `libexec`
  and exposing one launcher in `bin`. Because the release bundles ERTS, the brew
  erlang pin and the runtime `depends_on "erlang"` both fall away. This is the
  simplest packaging that fully removes the mismatch.
- **Burrito single-binary.** Burrito is genuinely better when the distribution
  goal is prebuilt, download-and-run binaries across macOS/Linux/Windows with no
  toolchain. That is not the Homebrew model, where the formula compiles from
  source. Adopting Burrito now would add a Zig cross-compilation dependency to
  solve a problem (toolchain-free prebuilt distribution) we do not currently
  have. Recorded as a clean re-entry point, not taken.

The release composes well with the rest of the stack. The
`filter.gitfoil.process` long-running protocol added in v1.1.0 already
`dlopen`s the NIFs once at startup and serves every file over one process; a
release reinforces that path (single boot, single load, no per-file race) and
makes the legacy per-file `clean`/`smudge` fallback load natively too. Rustler's
default load path is the release's `priv/native`, so the NIF modules need no
change. The pqclean dependency ships its precompiled `.so` in its own `priv`,
which a release places correctly with zero staging.

## How it serves the role

Trace one `git add secret.txt` on a release-distributed install. Git runs the
`bin/git-foil` launcher in the release tree. The launcher boots the bundled
ERTS — the same version the NIFs were compiled against, so no ABI check can
fail. `GitFoil.Native.AegisNif` loads; Rustler resolves
`:code.priv_dir(:git_foil)` to `lib/git_foil-1.1.x/priv/native/` and `dlopen`s
`libaegis_nif.so`, a real file that has been sitting on disk since `brew
install`. No module attribute was read at compile time, no bytes were extracted
to a cache, no second process is racing to write the same file. `clean` returns
a valid `0x03`-prefixed blob; `smudge` reverses it. The tool does the one job it
exists to do, and the four workaround modules that made v1.1.0, v1.1.1, and
v1.1.2 fragile are gone from the codebase.

## Consequences

- **Gains:** NIFs load by the standard mechanism with no embedding or
  extraction. The compile-order bug class is structurally impossible. The
  `dlopen`-race retry loop and the brew-erlang ABI pin become unnecessary.
  `rustler_loader.ex` and `pqclean_loader.ex` are deleted. Build-ERTS equals
  runtime-ERTS by construction.
- **Costs:** This is a one-way door on the shipped artifact. The Homebrew
  formula, the wrapper, the `filter.gitfoil.process` registration, and the
  rollback/downgrade story all change shape and need end-to-end re-verification
  (the isolated-keg roundtrip, the filter-process protocol under real `git`, and
  a downgrade test). A release tree is larger on disk than a single escript file.
- **Risks:** The downgrade path between an escript-era install and a release-era
  install is the sharp edge, since the wrapper and filter wiring differ;
  `docs/process-filter-rollback-hole` already documents one such trap and the
  migration must extend it. If prebuilt distribution is ever wanted, a release
  tree alone does not provide it and Burrito (and precompiled-NIF handling)
  re-enters scope.

## What changes at 10x

The decision should be revisited if the distribution model shifts from
"Homebrew builds from source" to "ship prebuilt binaries to users without a
toolchain" — at that point Burrito plus precompiled or `rustler_precompiled`
NIFs becomes the relevant pattern, and the single-binary packaging this ADR
defers becomes load-bearing. It should also be revisited if Windows support is
targeted (the current release config is Unix-only) or if the NIF count grows
enough that per-target build time on `brew install` becomes a user-visible cost,
which would again push toward shipping precompiled artifacts.

## References

- `docs/MIX_RELEASE_GUIDE.md` — existing release build that loads NIFs natively.
- `lib/git_foil/native/rustler_loader.ex`, `lib/git_foil/native/pqclean_loader.ex` — the workaround machinery this decision removes.
- `Formula/git-foil.rb` — current escript packaging + wrapper (ABI pin, retry loop).
- v1.1.3 fix (escript compile-order hardening) — the interim measure this ADR is deferred behind.
- `docs/process-filter-rollback-hole` (memory) — downgrade hazard the migration must account for.
- Elixir `mix release` documentation; Burrito (burrito-elixir) for the optional single-binary path.
