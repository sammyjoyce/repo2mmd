# Documentation

This directory hosts the living documentation for repo2mmd. Start with the high-level plan and architecture, then drill into language plugins, configuration, and contributor guides.

## Index

| Path | Audience | Summary |
| --- | --- | --- |
| [../PLAN.md](../PLAN.md) | Product & engineering | Scope, goals, roadmap, metrics. |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Developers | Pipeline, components, plugin architecture, operational model. |
| [ir-schema.md](./ir-schema.md) | Tooling integrators | JSON schema for nodes, edges, manifest, and diagnostics. |
| [config.md](./config.md) | Users & CI owners | Configuration precedence, file format, and CLI/environment overrides. |
| [plugins/overview.md](./plugins/overview.md) | Plugin authors | ABI contract, lifecycle, testing, and distribution guidance. |
| [ZIG_PRIMER.md](./ZIG_PRIMER.md) | New Zig contributors | Language primer tailored to this project. |
| [demos/](./demos/) | Users | Example inputs/outputs and usage walkthroughs. |

### Contribution Tips

- Update the relevant document alongside code changes; treat docs as first-class deliverables.
- Prefer concise sections with links to deeper references rather than duplicating content.
- Keep diagrams in Mermaid for ease of review; the CI pipeline renders them for release notes.
