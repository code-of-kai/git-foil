# GitFoil v0.9 Implementation Research Notes

**Author:** Codex AI agent  •  **Date:** 2025-10-14

---

## Context
- Source document reviewed: `docs/V09_ARCHITECTURE_AND_IMPLEMENTATION_PLAN.md` (GitFoil v0.9).
- Current implementation (v0.8) relies on an escript-driven clean/smudge filter that fails to load Rust NIFs, so encryption/decryption is currently broken whenever Git runs the filter.
- `.gitattributes` in the repo applies the `gitfoil` filter to `**`, meaning every tracked file triggers the failing clean filter during `git status`, `git add`, etc.

---

## Key Takeaways from the Plan
1. **Architectural pivot**
   - Replace escript entrypoint with a Mix release bundled with NIFs.
   - Move from per-invocation filters to Git's long-running *process filter* protocol for <20 ms per-file performance.

2. **Cryptographic format changes**
   - Introduce a 45-byte Header V1 (`magic` + `kid` + `alg` + `nonce`) prepended to every blob.
   - Support key rotation via `keys.json`, allowing multiple KIDs and future algorithms.

3. **Command surface expansion**
   - New CLI verbs: `git-foil filter --process`, `git-foil key <generate|list|activate|export|import>`, and `git-foil audit`.
   - `git-foil init` must configure both process filters and legacy clean/smudge fallbacks.

4. **Distribution & DX**
   - Adopt `mix release` with `rustler_precompiled` artifacts distributed per target triple.
   - Update CI to build and attach precompiled NIFs to GitHub releases.

5. **Testing & Performance**
   - Add comprehensive integration tests covering process filter flows, multi-key rotation, and performance baselines (e.g., 1000-file loop with memory guardrails).

---

## Scoped Deliverables & Suggested Milestones

| Milestone | Summary | Primary Outputs | Dependencies |
|-----------|---------|-----------------|--------------|
| **M1. Format & Storage Foundations** | Implement header encoder/decoder, keystore (`keys.json`), and migration from `master.key`. | `GitFoil.Crypto.Header`, `KeyManager.Store`, migration utilities, unit tests. | Adds `jason` dependency; ensure compatibility with existing tests. |
| **M2. Process Filter & CLI Skeleton** | Build pkt-line utilities, process filter loop, and `git-foil filter --process` command. | `GitFoil.Filter.PktLine`, `GitFoil.Filter.ProcessProtocol`, CLI routing + smoke tests. | M1 complete; NIF calls remain via existing engine. |
| **M3. Release Packaging** | Configure `mix release`, `rustler_precompiled`, CI workflow, and NIF warm-up. | Updated `mix.exs`, `rel/` scripts, GitHub Actions workflow, documentation. | Requires M2 to validate filter binary in release. |
| **M4. Command Surface Updates** | Update `git-foil init`, add key management and `audit` commands, adjust helper messaging. | Revised command modules, help text, user prompts, targeted tests. | M1–M3 provide underlying primitives. |
| **M5. Test & Perf Hardening** | Add integration suite for process filter, key rotation, legacy fallback, plus benchmarks. | `test/integration/process_filter_test.exs`, perf harness, docs for expected metrics. | Build artifacts from M2–M4. |

Each milestone is large but independently reviewable, enabling incremental PRs instead of a single massive drop.

---

## Immediate Recommendations
- **Stabilize developer workflow**: temporarily set `filter.gitfoil.clean/smudge` to `cat` (as documented in TEST_RESULTS_LOG.md) so contributors can run `git status` without escript failures until the process filter lands.
- **Bootstrap dependencies**: add `:jason` (for JSON keystore) and ensure pqclean/Rustler versions align with release tooling requirements.
- **Start with M1**: implementing the header + keystore unlocks later milestones and can be validated with unit tests without touching filter plumbing.
- **Documentation strategy**: keep `docs/V09_ARCHITECTURE_AND_IMPLEMENTATION_PLAN.md` as the umbrella vision; branch-specific ADRs should accompany each milestone to capture deviations and learnings.

---

## Open Questions / Risks
1. **Backward compatibility**: how will repositories encrypted with the old format migrate? Need a compatibility story (e.g., detect v3 blobs and fall back until rekeyed).
2. **Windows support**: process filters behave differently on Windows; testing matrix must cover it before shipping.
3. **Key export/import UX**: password prompts, confirmations, and failure modes need to be spec’d (especially for automation).
4. **Performance validation**: concrete baselines (hardware, dataset size) must be defined so the <20 ms target is measurable and CI-enforced.
5. **Security audit**: new keystore and header logic should undergo review (e.g., verifying random nonce generation, preventing KID collisions).

---

## Next Steps
1. Review and approve the milestone breakdown above (adjust scope if required).
2. Create tracking issues/PR checklist per milestone.
3. Allocate time for migration scripts and backward-compat tests ahead of the process-filter cutover.
4. Once milestones are confirmed, I can begin with M1 implementation in a dedicated branch.

---

*These notes capture the concrete findings from the initial 34-minute planning pass so stakeholders have a tangible artifact and an actionable roadmap.*
