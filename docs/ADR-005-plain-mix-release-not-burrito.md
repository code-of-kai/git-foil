# ADR 005: Use a plain mix release, not Burrito, for packaging

- **Status:** Proposed (refines ADR-004; deferred behind the v1.1.3 escript fix)
- **Date:** 2026-06-01
- **Deciders:** code-of-kai

## Context

ADR-004 decides that git-foil should be distributed as an OTP release rather
than an escript, so the Rust NIFs load by the standard mechanism instead of the
embedding workaround. That decision settles the *format category*. It does not
settle *which release tool* produces the artifact, and the repo currently
contains a misleading signal about that choice.

`build_release.sh` reads as though Burrito is the intended packaging path: it
echoes "Building GitFoil standalone binaries with Burrito", deletes a
`burrito_out/` directory, and after building tries to `ls burrito_out/` and run
`./burrito_out/git_foil_macos_arm64`. None of that works. The script's actual
build command is a plain `mix release`, which emits to
`_build/prod/rel/git_foil/`, not `burrito_out/`. Burrito is not a dependency in
`mix.exs` or `mix.lock`. The `burrito_out/` references point at paths a plain
release never creates, so the script would fail if run. It is a leftover from an
abandoned experiment, not infrastructure. Reading it as "Burrito is already set
up" would be a factual error, and the kind of error that sends a future
implementer down the wrong path.

This record fixes the choice deliberately so the stale script cannot be mistaken
for a decision.

## The pattern

The need is **self-contained runtime bundling**: ship the BEAM runtime, the
bytecode, and the native libraries together so the tool runs identically
regardless of what Erlang the host has. Within that need there are two distinct
mechanisms:

- **A plain OTP release** (`mix release`) produces a directory tree containing a
  private copy of ERTS, every application's `ebin` and `priv`, and boot scripts.
  ERTS bundling is on by default (`include_erts: true`). The artifact is a tree
  with a launcher; it runs on the platform it was built on.

- **A single self-extracting binary** (Burrito) wraps that release into one file
  with a cross-compiled, bundled runtime, so a maintainer can build binaries for
  several OS/architecture targets from one machine and hand a user a single
  download that needs no toolchain.

These differ only in packaging and cross-compilation, not in how NIFs load. Both
bundle ERTS; both place `.so` files in `priv/native` where Rustler finds them.

## Decision

We will package git-foil as a **plain `mix release`**, relying on the default
`include_erts: true`. We will **not** adopt Burrito now, and we will delete or
rewrite the stale `build_release.sh` so it stops implying otherwise.

Burrito is recorded as the mechanism to adopt **if and only if** the
distribution model changes to shipping prebuilt cross-platform binaries to users
without a build toolchain.

## Rationale

The single concrete problem a release must solve for git-foil, beyond loading
NIFs natively, is the runtime ABI coupling. The current escript borrows whatever
`erl` leads `PATH`, which is why the Homebrew wrapper hard-pins
`PATH="brew erlang"`: the precompiled pqclean NIF (`deps/pqclean/priv/pqclean_nif.so`)
must run under an ERTS whose NIF ABI matches the one it was built against. A
plain `mix release` already resolves this. `include_erts: true` copies the
build-time ERTS into the release, so runtime-ERTS equals build-ERTS by
construction. The reason the PATH pin exists, ambient-runtime borrowing, is gone.
The pqclean ABI requirement is then satisfied exactly as it is during the
`brew install` build today, with no wrapper gymnastics.

Burrito would also bundle a runtime and would also remove the pin. It is a
capable, well-regarded tool, and if the goal were "publish a macOS-arm64, a
macOS-x86_64, and a Linux binary from CI for users to download," Burrito (with
its Zig-based cross-compilation) would be the right answer and a plain release
would not. That is the case it is built for and it is genuinely better there.

It is not git-foil's case. Homebrew installs by compiling the formula from source
on the user's own machine, so the binary is always native to the target by
construction. The single-file, toolchain-free, cross-compiled distribution
Burrito provides is value the Homebrew model does not consume. Adopting it now
would add a Zig cross-compilation toolchain and a dependency to the build in
exchange for a capability we do not currently ship. That is cost without
corresponding benefit, and the "build_release.sh already mentions Burrito" signal
is not a reason to take it on, because that script does not actually work.

The plain release composes cleanly with the rest of the stack. Rustler's default
load path is the release's `priv/native`; pqclean's precompiled `.so` lands in
its own application `priv`; the `filter.gitfoil.process` long-running path boots
the release once and loads every NIF a single time. Nothing in the release
mechanism conflicts with the existing protocol or key handling.

## How it serves the role

Trace a `brew install` on the release-packaged formula. Homebrew compiles the
project against the brew Erlang, then `mix release` bundles that exact ERTS into
`libexec`'s release tree. When Git later invokes the launcher for a `clean`, the
launcher starts the bundled ERTS, the same one the NIFs and the precompiled
pqclean library were built against. `:code.priv_dir(:git_foil)` resolves to the
release's `priv/native`, the cipher `.so` files load, and the pqclean ABI check
passes because build-ERTS and runtime-ERTS are the same bytes. No `PATH` pin, no
ambient runtime, no single-binary cross-compilation step. The release tree is the
whole mechanism.

## Consequences

- **Gains:** The brew-erlang PATH pin in the wrapper becomes unnecessary, since
  the release bundles its own matching ERTS. No new build dependency. The
  simplest mechanism that fully satisfies ADR-004. The misleading
  `build_release.sh` gets corrected.
- **Costs:** The artifact is a directory tree, not a single file. Homebrew
  handles this natively under `libexec`, but it is more than one file on disk.
  A plain release targets the platform it is built on, so it does not, by itself,
  enable prebuilt cross-platform distribution.
- **Risks:** If prebuilt binary distribution is later wanted and this decision is
  forgotten, someone may rediscover the same `build_release.sh` and assume
  Burrito is wired up. Deleting or rewriting that script as part of executing
  this ADR is what closes that hole.

## What changes at 10x

Revisit this when the distribution model shifts from "Homebrew compiles from
source" to "ship prebuilt binaries users download and run." At that point
Burrito, paired with precompiled or `rustler_precompiled` NIFs, becomes the
correct mechanism and the single-binary cross-compilation deferred here becomes
load-bearing. Targeting Windows (the current release config is Unix-only) is the
same trigger.

## References

- ADR-004: Distribute git-foil as an OTP release, not an escript (this record refines it).
- `mix.exs` `releases/0` — the `mix release` config (no `include_erts` override, so it defaults to bundling ERTS).
- `build_release.sh` — the stale Burrito-referencing script this decision corrects.
- `Formula/git-foil.rb` — the wrapper's `PATH="brew erlang"` ABI pin that a bundled-ERTS release removes.
- `deps/pqclean/priv/pqclean_nif.so` — the precompiled NIF whose ABI requirement motivates the runtime-ERTS match.
- Elixir `mix release` documentation; Burrito (burrito-elixir).
