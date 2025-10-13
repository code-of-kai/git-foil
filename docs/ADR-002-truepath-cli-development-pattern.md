# ADR-002: TruePath CLI Development Pattern

**Status:** Accepted
**Date:** 2025-10-13
**Decision Makers:** Kai Taylor
**Related ADRs:** ADR-001 (Triple-Layer Quantum-Resistant Encryption)

## Context

When developing Elixir CLI tools, developers face a critical **name resolution and PATH precedence problem**. Multiple versions of the same CLI command exist simultaneously:

1. Production version installed via Homebrew (e.g., `/opt/homebrew/bin/git-foil`)
2. System-installed version (e.g., `/usr/local/bin/git-foil`)
3. Development version in project directory (e.g., `./git-foil-dev`)
4. Old escripts in Mix install directories (e.g., `~/.asdf/.../escripts/git-foil`)

**The Problem:** When a developer types `git-foil`, which version actually runs?

This creates confusion for:
- **Human developers** - Testing wrong version, stale code, wasted debugging time
- **AI coding agents** - Cannot reliably invoke correct version, unclear state
- **CI/CD pipelines** - Flaky tests due to version ambiguity

Previous approaches tried:
- Manual path typing (`bin/git-foil`) - tedious, error-prone
- Shell aliases - bespoke per-project, doesn't clean up
- Wrapper scripts with auto-rebuild - complex, fragile timestamp checking
- Adding project bins to PATH - pollutes PATH, doesn't scale

## Decision

We have adopted **TruePath**, a standardized CLI development pattern that solves the name resolution problem using industry best practices.

### Core Principles

1. **Type the real command name** - Developer types `git-foil`, not `bin/git-foil` or wrapper names
2. **Industry standards over bespoke solutions** - Use XDG Base Directory, not custom approaches
3. **Zero ambiguity** - Only one version in PATH, clearly identified
4. **Zero manual rebuilds** - Mix handles recompilation automatically

### Technical Solution

TruePath uses **symlink management with XDG standards**:

```
~/.local/bin/git-foil  (in PATH)
    ↓ (symlink)
/path/to/project/bin/git-foil  (wrapper script)
    ↓ (executes)
mix foil  (Mix task, auto-recompiles)
    ↓ (calls)
GitFoil.CLI.main(args)
```

### Implementation Components

#### 1. `bin/setup` - One-time Configuration
- Creates `~/.local/bin/git-foil` symlink pointing to project's `bin/git-foil`
- Ensures `~/.local/bin` exists and is in PATH
- Adds PATH configuration to `~/.zshrc` or `~/.bashrc` if needed
- Idempotent (safe to run multiple times)
- Provides friendly feedback with emojis

#### 2. `bin/git-foil` - Development Wrapper
- Resolves symlinks to find project root (macOS and Linux compatible)
- Changes directory to project root
- Executes `mix foil` which auto-recompiles stale code
- Passes all arguments through to CLI

#### 3. `bin/float` - Production Escript QA
- Builds production escript: `MIX_ENV=prod mix escript.build`
- Runs the actual binary end users will receive
- Used for pre-release testing to catch escript-specific issues
- Name chosen for metaphor: "float a trial balloon" before release

#### 4. `lib/mix/tasks/foil.ex` - Mix Task
- Loads application
- Calls `GitFoil.CLI.main(args)` with command-line arguments
- Mix automatically recompiles changed files before running

### Workflow

**One-time setup:**
```bash
bin/setup
```

**Daily development:**
```bash
git-foil init              # Just type command name
git-foil configure "*.env"
# Edit code, run again - always fresh, auto-recompiles
```

**Pre-release QA:**
```bash
bin/float --version
bin/float init
```

## Rationale

### Why XDG Standard (~/.local/bin)?

1. **Industry standard** - Defined by freedesktop.org specification
2. **Used by professional tools** - Cargo (Rust), Pipx (Python), Go toolchain
3. **Clean PATH management** - Single directory, many commands
4. **Self-documenting** - `ls ~/.local/bin` shows all dev tools
5. **Easy cleanup** - Remove symlink when done with project

### Why Symlinks vs. Alternatives?

**Rejected: Shell aliases/functions**
- ❌ Pollutes shell config permanently
- ❌ Doesn't clean up when project deleted
- ❌ Hard to manage across projects
- ❌ Not discoverable

**Rejected: Adding project bin/ to PATH**
- ❌ PATH grows unbounded with projects
- ❌ Performance impact (shell searches many directories)
- ❌ Maintenance nightmare (stale entries)
- ❌ Not recommended by any professional guide

**Accepted: Symlinks to ~/.local/bin**
- ✅ Follows XDG standard
- ✅ Clean, auditable, manageable
- ✅ Standard practice in professional ecosystems
- ✅ Easy to add/remove/update

### Why Mix Tasks vs. Custom Scripts?

**Mix provides:**
- Built-in dependency tracking (recompiles only what changed)
- Standard Elixir tooling (no external dependencies)
- Works identically across all Elixir projects
- AI agent compatible (simple commands, no REPL)

**Custom rebuild scripts were:**
- Complex timestamp checking logic
- Error-prone (missed dependencies, false positives)
- Non-standard (required learning bespoke systems)

## Consequences

### Positive

1. **Unambiguous execution** - Developer types `git-foil`, correct version runs
2. **Zero manual rebuilds** - Mix handles recompilation automatically
3. **AI agent compatible** - Simple commands, deterministic behavior
4. **Reusable pattern** - Template works for all Elixir CLI projects
5. **Industry alignment** - Uses XDG standards, professional best practices
6. **Clean workspace** - No PATH pollution, no shell config clutter
7. **Easy onboarding** - New developers run `bin/setup` once

### Negative

1. **One-time setup required** - Must run `bin/setup` (automated, idempotent)
2. **Symlink management** - Adds dependency on `~/.local/bin` (standard location)
3. **Shell restart needed** - If PATH configured, must reload shell or restart terminal

### Neutral

1. **Development vs. production split** - Daily dev uses `git-foil`, QA uses `bin/float`
2. **Mix task dependency** - Requires Mix (already required for Elixir projects)

## Implementation History

### Phase 1: Legacy Cleanup (2025-10-13)
- Removed `.zshrc_snippet` (referenced non-existent `gfd.sh`)
- Removed `scripts/mix-run.sh` (154 lines of legacy wrapper)
- Removed `docs/VERSION_CONFUSION_SCENARIOS.md` (224 lines)
- Unified escript name from `git-foil-dev` to `git-foil`
- Simplified `INSTALL.md` to standard escript build

**Result:** Clean slate, removed 380+ lines of legacy patterns

### Phase 2: TruePath Implementation (2025-10-13)
- Created TruePath template repository at `/Users/kaitaylor/Documents/Coding/truepath/`
- Implemented `bin/setup` with XDG symlink management
- Implemented `bin/float` for production escript QA
- Updated `bin/git-foil` with symlink resolution (macOS/Linux compatible)
- Applied TruePath pattern to git-foil project
- Tested complete workflow: setup, development, float

**Result:** Working implementation, name resolution problem solved

### Phase 3: Documentation (2025-10-13)
- Added Engineering Principles to `/Users/kaitaylor/Documents/Coding/AGENTS.md`
- Created comprehensive TruePath README
- Documented industry best practices rationale
- This ADR

## Alternatives Considered

### 1. Direnv + Complex Tooling
**Rejected:** Requires external tools, complex setup, not AI-agent friendly

### 2. Justfile Task Runner
**Rejected:** Non-standard, requires learning bespoke commands, not portable

### 3. Shell Wrapper with Auto-rebuild
**Rejected:** Complex timestamp logic, fragile, error-prone

### 4. Docker Development Containers
**Rejected:** Heavy, slow, overkill for CLI development

### 5. Mix Aliases
**Rejected:** Still requires typing `mix alias-name`, doesn't solve PATH precedence

## Related Decisions

- **ADR-001:** Encryption architecture (TruePath enables testing encryption features)
- **Development Workflow:** Simplified from complex tooling to Mix-based pattern

## References

- XDG Base Directory Specification: https://specifications.freedesktop.org/basedir-spec/
- Cargo (Rust) uses `~/.cargo/bin` (similar pattern)
- Pipx (Python) uses `~/.local/bin` (identical pattern)
- TruePath template: `/Users/kaitaylor/Documents/Coding/truepath/`

## Lessons Learned

### Engineering Principle Applied

From `AGENTS.md` Engineering Principles:

> **Industry Best Practice First:** Always ask yourself when creating new solutions or engineering solutions: "What is industry best practice?"

We researched how Cargo, Pipx, and other professional tools solve PATH management. The answer: XDG-compliant `~/.local/bin` with symlinks.

> **Avoid the Doom Loop:** If it's taking you more than 3-4 iterations to get something correct (bug-free), STOP. You may be stuck in a doom loop of quick fixes driven by false urgency.

Previous approaches (wrapper scripts, aliases) required constant fixes and edge case handling. We stepped back, asked "How would we design this from scratch?", and discovered the clean symlink solution already exists as an industry standard.

### Key Insight

**Don't patch existing broken patterns. Research industry standards and adopt them.**

The name resolution problem has been solved by professional tooling ecosystems for decades. We didn't need to invent a solution; we needed to apply existing best practices to Elixir CLI development.

## Status: Accepted

TruePath is now the canonical pattern for:
1. git-foil development
2. Any future Elixir CLI projects
3. Recommended pattern for the Elixir community

## Approval

- **Author:** Kai Taylor
- **Date:** 2025-10-13
- **Commits:**
  - `4ba2193` - Remove legacy development pattern artifacts
  - `2ddf23d` - Implement TruePath pattern - solves name resolution problem
