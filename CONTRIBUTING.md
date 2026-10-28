# Contributing to repo2mmd

Thanks for your interest in improving repo2mmd! This guide explains how we
work, how to set up your environment, and what we expect from contributions.

---

## Code of Conduct

We expect all contributors to follow the
[Code of Conduct](CODE_OF_CONDUCT.md). Be respectful, patient, and
collaborative.

---

## Ways to contribute
- **Issues** – Report bugs or request features. Include reproduction steps,
  expected/actual behaviour, Zig version, and platform details.
- **Docs** – Fix typos, clarify workflows, or expand architecture sections.
- **Code** – Implement roadmap items, improve tests, or optimise existing
  modules. Reference the related milestone from [`PLAN.md`](PLAN.md).

Before filing a new issue, please search existing ones to avoid duplicates.

---

## Development workflow

1. **Fork** the repository and create a feature branch from `main`.
2. **Enable pre-commit hooks** (optional but recommended):
   ```bash
   pip install pre-commit
   pre-commit install
   ```
3. **Follow naming conventions** documented in [`AGENTS.md`](AGENTS.md)
   (lowerCamelCase for functions, UpperCamelCase for types, explicit units).
4. **Run tests and formatters** before submitting:
   ```bash
   zig build fmt-check
   zig build test
   ```
5. **Write clear commits** using Conventional Commits format, e.g.
   `feat(graph): add discovery walker`.
6. **Open a pull request** with context, screenshots (for UX), and test output.

---

## Environment setup

### Prerequisites
- Zig 0.15.1 exactly. `build.zig` refuses other versions; see
  [Toolchain](README.md#toolchain).
- Git, for the Tree-sitter submodules. No system C compiler is needed: Zig
  compiles the C plugins.
- `just` (optional task runner)

### Clone & build

```bash
git clone --recurse-submodules https://github.com/sammyjoyce/repo2mmd.git
cd repo2mmd

# Debug build
zig build

# Run the CLI skeleton
zig build run -- --help

# Execute the test suite
zig build test
```

Use `just fmt`, `just test`, and `just check` for project shortcuts.

### Devcontainer

The repository ships a `.devcontainer/` configuration. Open the folder in VS
Code and choose **Reopen in Container** to get a reproducible environment with
Zig, libclang, and tooling pre-installed.

---

## Testing expectations
- Add unit tests alongside new modules in `test/`.
- Update golden fixtures when emitters change; review diffs carefully.
- Run `zig build test -Doptimize=ReleaseSafe` for performance-sensitive
  changes.
- For CLI changes, extend `test/cli_graph.zig` (or create new focused tests)
  covering the behaviour.

---

## Documentation expectations
- Update `docs/` when behaviour, flags, or architecture change.
- Keep `PLAN.md` status in sync for the milestone you touched.
- When adding CLI flags, update `opencli.json` and help text in `src/`.

---

## Release process

Releases follow semantic versioning. When preparing a release:

1. Ensure `CHANGELOG.md` has entries under a dated heading.
2. Run `just check` (fmt + tests).
3. Tag the release (`vX.Y.Z`) and push.
4. Attach generated artefacts (binary + plugins) once emitters are active.

---

Have questions? Open a discussion or ping @sammyjoyce in the issue you are
working on. Thanks for helping build repo2mmd!

