# Frontier Zig

A Zig-hosted prototype that mirrors the architecture of `~/code/frontier`: Blitz will continue to render HTML/CSS, Bun will execute TypeScript with SQLite access, and a Zig executable will orchestrate everything.

## Project Layout

```
frontier-zig/
├── zig/          # Zig host application and build files
├── rust/         # (Phase 1+) Rust cdylib wrapping Blitz
├── bun/          # (Phase 3+) Bun helper for TypeScript and SQLite
├── assets/       # Static assets and demo HTML
├── scripts/      # CI helpers and automation
└── plans/        # Implementation roadmap
```

## Getting Started

```bash
# Run the demo application
just run

# Run CI pipeline (fmt + build + tests)
just ci

# Run tests directly
zig build test --build-file zig/build.zig
```

For a tour of the broader roadmap, see `plans/demo.md`.

## Phase 0 Goals

- Establish repository layout with placeholders for Zig, Rust, Bun, and assets
- Provide repeatable build/test commands via `just` and Nix flake outputs
- Stub dependency steps so future phases can plug in Blitz and Bun builds

Later phases will incrementally fill in the renderer bridge, navigation, Bun RPC loop, and SQLite wiring.

