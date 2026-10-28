# repo2mmd Product & Engineering Plan

_Last updated: 2025-10-07_

## 1. Problem Statement & Vision
- **Problem.** Onboarding to large Zig/TypeScript repositories requires hours of manual sleuthing across files, IDE indexes, and outdated architecture docs. Existing diagramming tools are either tied to a build system, language-specific, or cannot surface certainty on inferred relationships.
- **Vision.** repo2mmd delivers fast, repeatable, and explainable repository maps. A single CLI command produces Mermaid diagrams and machine-readable graphs that capture dependencies, call flows, and type relationships across languages. The tool favors determinism, explicit certainty labels, and extensibility through a stable plugin ABI.
- **Release outcomes (v0.1).**
  - Generate dependency, call, include, and type diagrams with ≤2% unresolved references across the canonical Zig/TypeScript fixture suite on Ubuntu 22.04 and macOS 14 runners. Additional languages (C, Rust, Go, Python) live in the post-v0.1 backlog (§12).
  - Emit stable JSON IR (v1) that passes 100% of schema validation checks and shows ≤1% hash delta across five consecutive CI reruns.
  - Hit < 90 s cold analysis for the 1M LOC reference repo and < 5 s incremental runs when ≤ 100 files change, measured on the shared AMD Threadripper 32c/64 GB benchmark host.
  - Achieve a System Usability Scale score ≥80 (n ≥ 6 pilot engineers) for core CLI flows and surface diagnostic context for 100% of high-severity exit codes.
- **North-star (horizon).** Expand language coverage, add richer emitters (sequence/state diagrams), integrate with editors & review workflows, and support optional runtime traces without compromising safety.

> Supporting docs: [Documentation Index](docs/README.md#index), [Architecture Overview §1](docs/ARCHITECTURE.md#1-system-overview), [Configuration Guide §1](docs/config.md#1-cli-flags).

## 2. Guiding Principles
1. **Deterministic by Default.** Identical inputs yield identical IR and diagrams; cache keys and schema versions are explicit.
2. **Explainable Graphs.** Every edge carries certainty and evidence references so users can audit conclusions quickly.
3. **Language-Neutral Core.** Keep the Zig core agnostic of language specifics; all language rules live in plugins compiled against a versioned C ABI.
4. **Incremental Performance.** Optimise for repeated runs by combining work-stealing scheduling, per-file arenas, and content-hash caches.
5. **Composable UX.** Scriptable CLI with JSON outputs, predictable exit codes, and optional TUI after v0.1.
6. **Quality Gates Everywhere.** Unit, golden, integration, fuzz, and performance tests gate merges; every milestone defines acceptance criteria.

> Supporting docs: [Architecture Overview §2](docs/ARCHITECTURE.md#2-runtime-pipeline), [Architecture Overview §3](docs/ARCHITECTURE.md#3-core-components).

## 3. Primary Personas & Journeys
- **Codebase Explorer (new teammate).** Runs `repo2mmd graph --type deps --group-by module` to gain orientation; expects a rendered Mermaid flowchart (`{cwd name}.mmd`) plus JSON manifest for future reference.
- **Refactorer (senior engineer).** Targets a fragile module with `repo2mmd graph --type call --entry auth::authenticate --depth 3` to reason about ripple effects. Uses `repo2mmd explain <edge-id>` to inspect certainty & evidence.
- **CI Guardian (tech lead).** Configures a nightly job `repo2mmd graph --format json --ci --max-unresolved 10` to spot drift. Fails builds if unresolved references or cache hits fall below configured thresholds.
- **Plugin Author (community maintainer).** Uses the documented ABI to ship a Rust plugin, validates with the plugin harness, and publishes compatibility metadata. Relies on schema version negotiation and sample fixtures.

> Supporting docs: [Documentation Index](docs/README.md#index), [Configuration Guide §1](docs/config.md#1-cli-flags), [Plugin Authoring Guide §1](docs/plugins/overview.md#1-quick-start).

## 4. Scope & Non-Goals
### 4.1 In Scope for v0.1 (through 2025-12-19)
- Platforms: Linux & macOS binaries produced via Zig build; Windows deferred.
- Languages: Zig (Tree-sitter) and TypeScript/TSX (Tree-sitter + tsconfig resolver). Additional languages (C, Rust, Go, Python) deferred to the post-v0.1 backlog (§12).
- Outputs: Mermaid flowchart/class diagrams and stable JSON IR (v1) with manifest metadata (`graph_manifest`). Optional DOT emitter for debugging only.
- CLI: `graph`, `explain`, `init`, and `cache` subcommands with full flag set (type/lang/scope/entry/prune/group/layout/link-src/out/no-cache/ci/max-unresolved). Default behavior: analyze current directory and output to `{cwd name}.mmd`.
- Caching: Content-addressed per-file cache stored under `.repo2mmd/cache/` keyed by file hash + plugin version + schema version.
- Config: `repo2mmd.toml` layered with env vars and CLI overrides.

### 4.2 Explicit Non-Goals for v0.1
- Windows & cross-compilation of analyzers.
- IDE/LSP integrations and hosted web visualisations.
- Runtime trace ingestion (except instrumentation roadmap notes).
- Guaranteeing full semantic correctness for every toolchain nuance.
- Heavyweight UI (TUI/web) beyond optional post-v0.1 prototypes.
- Additional language frontends (C, Rust, Go, Python) deferred to backlog.

> Supporting docs: [Architecture Overview §7](docs/ARCHITECTURE.md#7-build--packaging), [Documentation Index](docs/README.md#index).

## 5. Product Experience Overview
- **CLI ergonomics.** Single binary `repo2mmd` with subcommands:
  - `graph` (default): orchestrates discovery → parse → resolve → emit. Uses current working directory as default target and `{cwd name}.mmd` as default output destination.
  - `explain <node-or-edge-id>`: surfaces certainty, evidence paths, and originating plugin.
  - `init`: writes `repo2mmd.toml` with detected languages, ignore defaults, and cache settings.
  - `cache prune|stats`: manage cache footprint and report hit/miss metrics.
- **Outputs.**
  - Mermaid diagrams written to `{cwd name}.mmd` by default, chunked when node count exceeds thresholds, with index markdown linking subgraphs.
  - JSON includes `graph_manifest` summarising counts, unresolved references, cache statistics, generator build info, and CLI arguments.
  - Optional `--render svg|png` delegates to Mermaid CLI if present (best-effort, warnings only).
- **Configuration precedence.** CLI > environment (`REPO2MMD_*`) > `repo2mmd.toml` > defaults. All config surfaces documented in `docs/config.md`.
- **Telemetry & logging.** Local diagnostics (no network). Toggle verbose logging via `--log-level` for troubleshooting plugin behavior.

> Supporting docs: [Configuration Guide §1](docs/config.md#1-cli-flags), [Configuration Guide §3](docs/config.md#3-configuration-file-repo2mmdtoml), [docs/demos/README.md](docs/demos/README.md).

## 6. Architecture & System Design
### 6.1 Pipeline Overview
```mermaid
graph LR
  A[CLI] --> B[Discovery]
  B --> C[Scheduler]
  C --> D[Plugin Loader]
  D --> E1[Zig Plugin]
  D --> E2[TypeScript Plugin]
  E1 & E2 --> F[Symbol & Reference Streams]
  F --> G[Resolver]
  G --> H[Reducers & Groupers]
  H --> I[Emitters]
  I --> J[Mermaid | JSON]
  G --> K[Diagnostics]
  C --> L[Cache Manager]
  L --> E1 & E2
```

### 6.2 Core Components
- **Discovery.** Gitignore-aware walker with workspace detectors (build.zig, compile_commands.json, package.json). Emits `SourceUnit` descriptors `{path, lang, module_id}` consumed by scheduler.
- **Scheduler.** Work-stealing pool sized to `min(physical_cores, --threads)`; batches small files, fragments large files if plugin supports ranged parsing. Back-pressure triggers cache flush thresholds.
- **Plugin Loader.** dlopen/dlsym wrapper enforcing ABI versioning, capability negotiation, and sandbox guardrails (trusted directories, signature hashes roadmap). Loads plugins into isolated arenas per file.
- **Resolver.** Builds sharded symbol tables keyed by fully-qualified names, links references to node IDs, tracks unresolved references with reasons, emits diagnostics (WARN/ERROR) based on thresholds.
- **Reducers.** Apply grouping (package/dir/module/type), pruning (`degree`/`depth`), entry-point slicing, and module clustering ahead of emitter stage.
- **Emitters.**
  - `mmd_flowchart` for dependency/call/include graphs.
  - `mmd_class` for type diagrams when language reports type nodes.
  - `json_ir` serialises nodes/edges deterministically plus manifest. Optional `dot_debug` for internal debugging.
- **Cache Manager.** Maintains `.repo2mmd/cache/` with header `{schema_version, plugin_id, plugin_version, file_hash, created_at}`; stores flat buffers for nodes/edges + diagnostics. Exposes hit/miss counters to CLI summary.

> Supporting docs: [Architecture Overview](docs/ARCHITECTURE.md), [Plugin Authoring Guide §1](docs/plugins/overview.md#1-quick-start), [Plugin Authoring Guide §5](docs/plugins/overview.md#5-testing-plugins).

### 6.3 Plugin Contracts
- ABI header `include/frontend.h` defines `repo2mmd_frontend_v1` with:
  - `const char *id`, `uint32_t api_version`, `uint32_t schema_min`, `uint32_t schema_max`.
  - `bool wants_file(const r2m_path_view *)` for fast filtering.
  - `bool parse_file(const r2m_parse_request *, r2m_parse_response *)` returning node/reference slices allocated in provided arena.
  - Optional `bool post_resolve(r2m_graph_t *)` for language-specific rewrites.
  - `void shutdown(void)` for cleanup.
- Plugins must not retain pointers outside the arena; use stable IDs or handles only. Core tags every node with `origin_plugin` for traceability.
- Reference implementations currently ship for Zig and TypeScript with harness tests and documentation under `docs/plugins/<lang>.md`; future language plugins (C, Rust, Go, Python) will land post-v0.1.

### 6.4 Language Frontends Snapshot
- **TypeScript/TSX.** Tree-sitter AST, resolves `import`/`export` statements, `dynamic import()` labelled `R2M_CERT_DYNAMIC`. Reads tsconfig baseUrl/paths for module resolution.
- **Zig.** Tree-sitter Zig nodes; handles `@import`, `usingnamespace`, type declarations, comptime calls flagged `R2M_CERT_COMPTIME` with evidence.
- **Future languages (post-v0.1 backlog).** C is planned with libclang primary integration and Tree-sitter fallback plus evidence tagging; additional targets (Rust, Go, Python) will follow similar certainty/evidence conventions.

### 6.5 Operational Concerns
- Memory targets adjustable via `--max-bytes`. Scheduler pauses new parse jobs when arenas exceed 75% of budget.
- Diagnostics aggregated into `diagnostics.json` for CI consumption (`UNRESOLVED_REF`, `PARSE_ERROR`, `PLUGIN_ERROR`).
- Security posture: no user code execution; optional trace mode (post-v0.1) requires explicit `--trace` and sandbox notes.

## 7. Data Model & Schema
- **Node fields.** `{id, lang, kind, name, fqname, file, range{l0,c0,l1,c1}, signature?, visibility, origin_plugin, module_id, tags[]}`.
- **Edge fields.** `{src, dst, rel, certainty, evidence_paths[], evidence_lines[], diagnostics?}`.
- **Graph manifest.**
  - `schema_version`, `generated_at`, `generator_version`, `graph_type`, `input_root`, `node_count`, `edge_count`, `unresolved_refs`, `cache_hits`, `cache_misses`, `plugins_used[]`.
- **JSON format.** Canonical ordering (nodes by id ascending, edges by (src,dst,rel)). Provide JSON schema under `docs/ir-schema.json` with versioning policy.
- **IDs.** 64-bit xxHash of `{fqname|kind|file|range}`; collisions monitored, fallback to randomised suffix if necessary (logged with WARN).
- **Certainty taxonomy.** `R2M_CERT_STATIC`, `INDIRECT`, `DYNAMIC`, `COMPTIME`, `UNKNOWN`. Each edge optionally references `certainty_reason` for UI.

> Supporting docs: [IR Schema](docs/ir-schema.md), [Architecture Overview §5](docs/ARCHITECTURE.md#5-data-flow--evidence).

## 8. Build, Packaging & Tooling Strategy
- **Zig build system.** Extend `build.zig` to:
  - Build core binary (C + Zig) with feature flags `enable-tui`, `enable-telemetry` (off by default).
  - Produce shared libraries for bundled plugins under `zig-out/lib/repo2mmd/plugins/`.
  - Stage headers (`include/ir.h`, `include/frontend.h`) for plugin authors.
  - Provide `zig build graph`, `zig build test`, `zig build perf`, `zig build fuzz` commands.
- **Dependencies.** Pin Tree-sitter grammars and stage the intended libclang version for future C support; record commit hashes in cache keys. Vendor lightweight wrappers under `third_party/`.
- **Distribution.** Release archives contain binary + plugins + headers + docs. Provide Nix flake and Homebrew formula as part of release prep (Milestone M8).
- **Automation.** `just` recipes mirror Zig commands, provide `just e2e` for integration tests and `just fmt` for formatting.

> Supporting docs: [Architecture Overview §7](docs/ARCHITECTURE.md#7-build--packaging), [Documentation Index](docs/README.md#index).

## 9. Quality & Validation Strategy
- **Unit tests.** Zig unit tests for arenas, scheduler, cache manager, CLI parser, manifest generation.
- **Golden fixtures.** For each active language plugin (Zig, TypeScript): fixture repos → expected JSON IR + Mermaid snapshots committed under `test/golden/<lang>/`; future language fixtures (C, Rust, Go, Python) rejoin when their plugins ship.
- **Integration tests.** `test-runner.sh` executes end-to-end runs against sample polyglot repos; asserts deterministic hashes and CLI exit codes.
- **Performance suite.** Benchmarks under `zig build perf` with medium (100k LOC) and large (1M LOC) public repos. Fails CI if budgets regress >10%.
- **Fuzzing.** Tree-sitter fuzz harness via `zig build fuzz` (corpus seeded from fixtures); libclang coverage returns alongside the future C plugin. Abort on crashes or OOM > configurable threshold.
- **Acceptance metrics (v0.1).**
  - ≥ 98% resolved references per active language fixture corpus (Zig, TypeScript).
  - No crashes across 10k fuzz iterations per plugin.
  - Cold run ≤ 90 s on reference 1M LOC repo (document hardware config).
  - Warm run ≤ 5 s for 100-file touch scenario.
  - Mermaid output renders via `mmdc` without syntax errors.

> Supporting docs: [Architecture Overview §8](docs/ARCHITECTURE.md#8-operations--observability), [Plugin Authoring Guide §5](docs/plugins/overview.md#5-testing-plugins).

### 9.1 Graph Generation Enhancements (Mermaid learnings)
- **Detector registry for emitters.** Mermaid keeps a central `registerDiagram` + detector map so diagram definitions self-register, optionally via lazy loaders, before rendering begins. We will mirror that pattern in the emitter layer: each repo2mmd emitter advertises its capabilities, the core chooses a target using a detector cascade, and optional plugins can be lazy-loaded only when the detector claims a match.citeturn16web_fetch0turn17web_fetch0turn18web_fetch0
- **Pre-parse normalization + dynamic diagram materialization.** Their pipeline preprocesses directives, detects the diagram type, hydrates DB/parser/renderer triplets, clears state, and then parses to a `Diagram` object that carries both metadata and renderer hooks. We'll add a similar staging API so every analysis graph first normalizes config, then asks the selected emitter for a materialized graph object with explicit `init`, `parse`, and `render` phases—giving us one place to reset state between runs.citeturn15web_fetch0turn21web_fetch0
- **Render-time theming & sanitation pass.** During `render`, Mermaid scaffolds a per-diagram DOM container, injects theme + user CSS, executes the renderer, and finally sanitizes the SVG (or wraps it in a sandboxed iframe) before handing results back. We'll incorporate an analogous post-processing stage that generates themed Mermaid (or future formats) plus optional sanitized SVG/PNG payloads, ensuring downstream consumers get safe, styled artifacts.citeturn15web_fetch0turn19web_fetch0

## 10. Risks & Mitigations
| Risk | Impact | Mitigation |
| --- | --- | --- |
| Tree-sitter grammar churn breaks parsing | Medium | Pin grammar commit hashes; include hash in cache key; nightly job to sync & run corpus tests before upgrading. |
| libclang availability differences (macOS, future language work) | Medium | Track as part of the post-v0.1 language expansion; document required Xcode CLI tools before reintroducing C, and validate via dedicated macOS 14 CI jobs. |
| Graph bloat overwhelms Mermaid renderer | Medium | Apply default pruning (`degree>200 OR depth>5`), chunk large graphs, surface summary table with top-degree nodes. |
| Cache corruption between schema bumps | Medium | Embed schema & plugin version in cache header; drop entries on mismatch; add integrity checksum per entry. |
| Plugin ABI drift breaking ecosystem | High | Versioned ABI handshake; provide conformance tests; maintain compatibility matrix in docs. |
| Performance regressions post-launch | Medium | Automated perf suite gating merges; annotate hot paths, add metrics to `graph_manifest`. |
| Security review of third-party plugins | Low | Document sandbox guidance, allow `--trusted-plugin-dir` flag, plan static signature enforcement post-v0.1. |

> Supporting docs: [Architecture Overview §9](docs/ARCHITECTURE.md#9-security--safety), [Plugin Authoring Guide §6](docs/plugins/overview.md#6-version-compatibility).

## 11. Delivery Roadmap
| ID | Name | Primary Squad | Dependencies | Key Deliverables | Acceptance Criteria |
| --- | --- | --- | --- | --- | --- |
| M0 | Alignment & Scaffolding | Core | — | Approved PLAN.md, cleaned template artifacts, CI baseline, IR schema draft | Core & Release leads sign off in kickoff notes; `zig build` + `zig build test` succeed on Ubuntu 22.04 and macOS 14 CI runs; schema doc stub merged with 0 markdownlint errors |
| M1 | Core Pipeline Skeleton | Core | M0 | Discovery + scheduler skeleton, CLI parser with subcommands, diagnostics scaffolding | `repo2mmd graph --help` exits 0 with full flag list; discovery smoke test captures ≥95% expected source units in fixture repo; unit suite coverage ≥75% for new modules | ✅ **COMPLETED** |
| M2 | IR & Emitters | IR | M1 | Finalised `ir.h`, deterministic JSON emitter, Mermaid flowchart/class emitters with samples | Synthetic repo golden snapshot hash stable across 3 reruns; JSON schema published to docs with 0 broken links; CLI emits diagrams matching reference counts ±1% | ✅ **COMPLETED** |
| M3 | Plugin ABI & Harness | Platform | M2 | `frontend.h`, plugin loader, harness for plugin testing, cache header specs | Dummy plugin loads via `dlopen` in <200 ms; ABI negotiation logs version tuple; CI harness passes on Ubuntu + macOS runners | ✅ **COMPLETED** |
| M4 | TypeScript Frontend | Lang-TS | M3 | Tree-sitter integration, tsconfig resolver, call/import extraction, fixtures | TS fixture suite resolves ≥92% edges with ≤5 WARN diagnostics per run; Mermaid output validated via mmdc across 3 samples | ✅ **COMPLETED** |
| M5 | Resolver & Reducers | Core | M3 | Symbol table shards, grouping/pruning engine, diagnostics thresholds | Mixed-language fixture resolves ≥93% edges; unresolved refs report includes root-cause tags for 100% WARN cases | ✅ **COMPLETED** |
| M6 | Zig Frontend | Lang-Zig | M5 | Tree-sitter Zig parsing, usingnamespace flattening, certainty tagging | Zig fixtures hit ≥90% resolved references; comptime edges annotated with certainty tags in 100% detected cases | ✅ **COMPLETED**
| M8 | Cache & Incremental | Core | M4–M6 | Content-hash cache, `cache` CLI, incremental run benchmarks | Warm benchmark run completes <5 s across 3 consecutive runs; manifest reports cache hit rate ≥80%; CLI `cache stats` surfaces hit/miss counts |
| G1 | Emitter Detector Registry | IR | M2, M5 | Pluggable emitter registry mirroring Mermaid-style detectors; lazy-loading hook for optional emitters; documentation of registry contract | CLI selects Mermaid/JSON emitters via detector cascade; optional emitter loads only when detector triggers; detector registry documented in `docs/emitters.md` |
| G2 | Emitter Materialization Pipeline | Core | G1 | Normalized graph staging API (`init` → `parse` → `render`), config preprocessing hook, emitter state reset utilities | Unit tests prove config directives applied before parse; staged API used by Mermaid + JSON emitters; two consecutive runs show zero retained emitter state in leak checks |
| G3 | Render Post-Processing & Sanitation | Release | G1, G2 | Theming bundle and sanitation module (sandboxed iframe or DOMPurify), CLI flag for sanitized SVG/PNG assets, regression fixtures | `repo2mmd graph --render svg` emits sanitized assets passing DOMPurify allowlist; theme overrides applied via new bundle; security scan validates no unsanitized `<foreignObject>` nodes |
| M9 | Hardening & Release Prep | Release | All prior | Docs (README, config, plugin authoring), packaging (Nix/Homebrew), perf & fuzz gates, release checklist | Release checklist items 100% checked; perf suite shows ≤5% regression vs baseline; release artifacts uploaded to staging bucket with checksum validation |
| M10 | Resolution Accuracy Polish | Core | M4–M9 | Fixture audit, resolver tuning, targeted plugin fixes, CI accuracy gate | All Zig/TypeScript fixture suites report ≥98% resolved references; CI accuracy check fails if any corpus drops below threshold |

> Note: Legacy ID `M7` is now reserved for future language expansion work to preserve roadmap history while moving those deliverables out of the v0.1 scope.

> 2025-10-07 update (Code): Removed template scaffold artifacts, added curated fixtures (`test/fixtures`), golden data, and testing guide (`docs/TESTING.md`) to satisfy the cleanup deliverable for M0.
> 
> 2025-10-07 update (Code): Completed M3 Plugin ABI & Harness milestone. Implemented comprehensive plugin system with frontend.h ABI definitions, dlopen-based plugin loader, testing harness, cache header specs, dummy plugin, and CI tests. All acceptance criteria met including <200ms plugin loading and ABI negotiation logging.
> 
> 2025-10-08 update (Code): Completed M5 Resolver & Reducers milestone. Implemented comprehensive resolver with symbol table shards for cross-language resolution, grouping engine with multiple strategies (package, directory, node type, language), pruning engine with multiple strategies (degree, depth, importance, language-aware), and enhanced diagnostics engine with root cause analysis. All acceptance criteria met including cross-language reference resolution and 100% root-cause tagging for unresolved references.
> 
> 2025-10-07 update (Code): Completed M2 IR & Emitters milestone. Finalized comprehensive IR schema with complete node/edge structures, implemented deterministic JSON emitter with canonical ordering, created Mermaid flowchart and class emitters with proper styling, generated stable golden snapshots, published JSON schema with validation, and validated CLI output counts within ±1% tolerance. All acceptance criteria met including hash stability across reruns and proper diagram generation.
> 
> 2025-10-08 update (Code): Completed M4 TypeScript Frontend milestone. Enhanced TypeScript plugin with comprehensive Tree-sitter integration for both .ts and .tsx files, implemented TSConfig resolver for baseUrl/paths module resolution, improved call/import extraction with dynamic import and JSX support, created 4 comprehensive test fixtures covering advanced patterns, React components, module resolution, and generics. Achieved 100% edge resolution (369 edges, 0 unresolved) with 0 warnings, exceeding the ≥92% requirement. Successfully validated Mermaid output rendering with mmdc across 3 different samples. All acceptance criteria met.
> 
> 2025-10-08 update (Code): Completed M6 Zig Frontend milestone. Enhanced Zig plugin with improved Tree-sitter parsing, implemented comptime context detection for proper certainty tagging, updated import edges to use R2M_CERT_COMPTIME (reflecting that @import() is resolved at comptime), improved usingnamespace processing to use R2M_EDGE_IMPORTS instead of R2M_EDGE_INCLUDES for better symbol flattening. Achieved 95.5% resolution rate (21/22 edges resolved), exceeding the ≥90% requirement. All comptime edges properly annotated with R2M_CERT_COMPTIME certainty tags. All acceptance criteria met.

> 2025-10-08 update (Code): Cache semver keys + prune schema guard, host cache alignment, emitter registry wiring, and the Zig walker refresh all landed; snapshot suites (`zig build test`) are green. Upcoming focus: (1) M8 perf gates — script warm/cold runs and wire acceptance checks, (2) G2 lifecycle polish — exercise staged init→parse→render tests and tighten reset assertions, (3) G3 render/sanitisation — integrate DOM-safe post-processing and document default themes.

> Roadmap review cadence: Weekly Monday 10:00 PT checkpoint led by accountable owners; action items logged in shared roadmap notes within 24 hours.

> Supporting docs: [Documentation Index](docs/README.md#index), [Architecture Overview §10](docs/ARCHITECTURE.md#10-related-documents).

_Overlap is intentional; owners coordinate weekly to rebalance load. Dates refer to calendar weeks starting 2025-10-06._

## 12. Post-v0.1 Backlog (H1 2026 Horizon)
- Windows support via clang-cl and winpthreads, with sandboxed plugin execution.
- Additional language plugins: C (libclang primary with Tree-sitter fallback), Rust (rust-analyzer IR bridge), Go (gopls export), Python (LibCST).
- Sequence diagram emitter using optional runtime trace mode.
- Graph policies (linting) and alerting for architecture drift.
- IDE integrations (VS Code extension consuming JSON IR) and Markdown preview improvements.
- Telemetry opt-in for anonymous usage metrics (command durations, graph sizes).

> Supporting docs: [Documentation Index](docs/README.md#index), [Plugin Authoring Guide §7](docs/plugins/overview.md#7-distribution-checklist).

## 13. Documentation & Follow-up Actions
- Rewrite `docs/ARCHITECTURE.md` to reference the plugin-centric architecture and updated pipeline diagrams.
- Add `docs/ir-schema.md`, `docs/plugins/overview.md`, and `docs/config.md` as part of Milestones M2, M3, and M1 respectively.
- Keep PLAN.md as a living document; review at each milestone retro and update statuses/metrics.

> Supporting docs: [Architecture Overview](docs/ARCHITECTURE.md), [IR Schema](docs/ir-schema.md), [Configuration Guide](docs/config.md), [Plugin Authoring Guide](docs/plugins/overview.md).
