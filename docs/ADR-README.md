# Architectural Decision Records

This directory holds GitFoil's Architectural Decision Records (ADRs): short,
durable documents that capture *why* a significant architectural choice was
made, so a future reader can understand the shape of the system without
re-deriving the reasoning.

## Why ADRs

GitFoil makes a handful of decisions that are expensive to reverse and easy to
misremember: the cryptographic layering, the post-quantum integration, and the
way the CLI is packaged and shipped. An ADR records the context, the options
considered, the choice, and the conditions under which the choice should be
revisited. The goal is that "why is it built this way?" has a written answer
that outlives any single conversation.

## Conventions

- **Location & filename:** `docs/ADR-NNN-kebab-case-title.md`, three-digit,
  zero-padded, numbered monotonically. Numbers are never reused or renumbered,
  even if an ADR is later superseded or a number is skipped.
- **One decision per file.** A record that tries to capture two decisions
  should be split.
- **Status values:** `Proposed`, `Accepted`, `Deferred`, `Superseded by NNNN`,
  `Rejected`. A `Deferred` record captures both the present-day choice and the
  direction intended for later, without committing to build it now.
- **Supersession over deletion.** When a decision is replaced, mark the old ADR
  `Superseded by NNNN` and link forward; the new ADR links back. The history is
  the point.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [001](ADR-001-triple-layer-quantum-resistant-encryption.md) | Triple-Layer Quantum-Resistant Encryption with Ascon Integration | Proposed |
| 002 | *(unused — number skipped; never renumber)* | — |
| [003](ADR-003-six-layer-maximum-quantum-resistance.md) | Six-Layer Maximum Quantum Resistance | Proposed |
| [004](ADR-004-otp-release-distribution-for-nifs.md) | Distribute git-foil as an OTP release, not an escript | Proposed (deferred behind the v1.1.3 escript fix) |
| [005](ADR-005-plain-mix-release-not-burrito.md) | Use a plain mix release, not Burrito, for packaging | Proposed (refines 004) |

> Note: ADR-002 has no file. The number is intentionally left as a gap rather
> than reassigned, per the monotonic-numbering convention above.
>
> ADR-004 and ADR-005 form a pair: 004 chooses the release *format* over the
> escript; 005 chooses the release *mechanism* (plain `mix release`) within it.
