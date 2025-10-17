# Codex Agent Instructions

This repository powers GitFoil, an Elixir application that layers multiple encryption steps onto Git workflows. Follow these guidelines when acting as an automated Codex agent here.

## Orientation
- Core Elixir source lives in `lib/git_foil`; CLI helpers are in `lib/git_foil/cli`.
- Native NIF code resides under `native/`; rebuild only when necessary.
- Tests live in `test/` and run through `mix test`.

## Workflow Expectations
- Work from the repo root and honor existing tooling (`mix format`, `.tool-versions`, scripts).
- Keep edits focused and minimal; add brief clarifying comments only when intent is non-obvious.
- Run `mix format` on touched `.ex` files before finishing changes.
- After Elixir edits, execute `mix test` (or a targeted subset) to catch regressions.
- Avoid long-running or blocking commands; flag them before running if essential.

## Safety Guidelines
- Never expose encryption keys, secrets, or generated ciphertext artifacts.
- Skip destructive build commands (`mix release`, forced dependency updates) unless explicitly requested.
- Prefer documenting external dependency needs over installing them globally.

## Collaboration Notes
- Summarize modifications in final responses with precise path references (for example ``lib/git_foil/...``).
- Call out unanswered questions, test gaps, or follow-up work needed so maintainers can respond quickly.
- If instructions conflict or seem ambiguous, pause and ask for clarification rather than guessing.

Keep responses tight, clear, and action-oriented so the human teammate can stay in flow.
