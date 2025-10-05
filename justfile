set shell := ["zsh", "-c"]

default := "run"

# Run the prototype host from source.
run:
    zig build run --build-file zig/build.zig

# Execute the Zig unit tests bundled in the build graph.
test:
    zig build test --build-file zig/build.zig

# Phase 0 CI placeholder routed through scripts/ci.sh.
ci:
    ./scripts/ci.sh
