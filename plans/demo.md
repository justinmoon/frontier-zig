# Frontier Zig Demo Plan

## Demo Goal
Ship an end-to-end prototype of a Zig-hosted desktop browser that:
- Displays a working address bar where users enter HTTP/HTTPS or local file URLs.
- Uses Blitz for HTML/CSS rendering (matching the current Frontier feel, dual-renderer optional).
- Executes `<script type="text/typescript">` tags and inline modules by compiling them with Bun at runtime.
- Exposes an embedded SQLite database that those scripts can query/write through Bun.
- Keeps the scope focused on these features; Nostr, Lightning, and other long-term goals are out of scope.

## Inspiration & Reuse
- Mirror the `~/code/frontier` layout for familiarity: Zig replaces Rust for the host shell while Blitz remains the renderer.
- Reuse concepts from the existing dual-renderer (Dioxus chrome + Blitz content) only if it shortens the path to a polished address bar; otherwise render simple chrome in Blitz-managed HTML.
- Maintain a flat directory structure similar to Frontier (src/, assets/, scripts/, plans/).

## High-Level Architecture
```
+--------------------------------------------------+
|               frontier-zig (Zig host)            |
|--------------------------------------------------|
|  Winit event loop + window creation              |
|  Blitz renderer bridge (Rust cdylib via C ABI)   |
|  Navigation controller (URL parsing, networking) |
|  Bun bridge process (TypeScript + SQLite)        |
|  Resource loader (HTTP/file -> HTML string)      |
|  Script dispatcher (extract TS, invoke Bun)      |
+---------------------------+----------------------+
                            |
                +-----------v-----------+
                |   Blitz Renderer      |
                |   (Rust, as in master)|
                +-----------------------+
                            |
                +-----------v-----------+
                |   Bun Runtime         |
                |   - TS transpile/run  |
                |   - SQLite access     |
                +-----------------------+
```

### Bun Responsibilities
- Watch `script[type="text/typescript"]` blocks supplied by Zig, compile with Bun’s TypeScript pipeline, and execute the resulting JavaScript.
- Provide a host API surface (e.g., `globalThis.frontier`) with:
  - `frontier.sqlite.query(sql, params)` backed by Bun's SQLite bindings.
  - `frontier.emit(event, payload)` to communicate back to Zig (postMessage-style via IPC).
- Ship with an on-disk SQLite database stored in the project data directory.

### Zig Host Responsibilities
- Own the application lifecycle, windowing, and nav state.
- Fetch documents (HTTP via Zig stdlib, file via filesystem) and inject them into Blitz.
- Parse HTML for TypeScript script tags, forward them to Bun, and re-inject execution results (e.g., DOM mutations via Blitz scripting hooks or a simple callback interface).
- Manage IPC with Bun (std pipes or Unix domain sockets) to send script payloads and receive callbacks.
- Provide simple APIs for DOM event bridging if needed (e.g., capturing button clicks -> Zig -> Bun -> SQLite).

### Blitz Integration
- Build Blitz as a Rust `cdylib` exposing the minimal window/document APIs required (mirroring current `ReadmeApplication` flow).
- Optionally embed a thin Dioxus address bar overlay; otherwise generate the chrome HTML directly in Zig before passing to Blitz.
- Ensure Blitz remains responsible only for rendering; script execution results (DOM updates) can be applied by re-loading HTML or, if feasible, by calling Blitz DOM mutation APIs.

## Implementation Phases

### Phase 0 — Project Bootstrap
- Initialize `~/code/frontier-zig` repository with `zig/`, `rust/`, `bun/`, `assets/`, `plans/` folders.
- Set up `zig/build.zig` to build the main executable and drive dependent builds (Rust cdylib, Bun assets).
- Add a `justfile` mirroring Frontier commands (`just run`, `just ci`).

### Phase 1 — Window + Renderer Skeleton
- Create Zig executable that opens a window via Winit and loads Blitz’s renderer surface (reuse window config from Frontier where possible).
- Hard-code loading of a local HTML string to validate Zig ↔ Blitz integration.
- Deliverable: `just run` opens a window with static HTML rendered.

### Phase 2 — Navigation & Address Bar
- Implement URL parsing, HTTP/file fetching, and navigation history in Zig.
- Render an address bar UI—either via Blitz-rendered HTML overlay or by reusing the Dioxus chrome from Frontier through the cdylib.
- Deliverable: Entering a URL fetches and renders the remote page.

### Phase 3 — Bun Service Integration
- Build a Bun command-line helper inside `bun/` (TypeScript) that exposes an RPC loop (JSON over stdio) handling:
  - `compile_and_run` for TS script blocks.
  - `sqlite_query` for database operations.
- Launch this helper from Zig at startup, keep the process alive, and exchange messages via async IO.
- Deliverable: Zig can send `console.log` commands executed in Bun and receive responses.

### Phase 4 — TypeScript Execution Pipeline
- Extend the HTML loader to extract `<script type="text/typescript">` blocks and `<script type="module">` files with `.ts` suffix.
- For each, send content + execution context to Bun; Bun compiles (using `Bun.Transpiler`) and runs it, exposing DOM APIs needed for the demo (e.g., ability to set element text via simple command messages back to Zig).
- Deliverable: A demo page shipped in `assets/demo.html` whose TypeScript runs (e.g., counter button) after rendering.

### Phase 5 — SQLite Support
- Use Bun’s `bun:sqlite` to open a database file determined by Zig (e.g., `~/.frontier-zig/db.sqlite`).
- Add RPC commands `sqlite_exec` and `sqlite_query` that return JSON rows to Zig.
- Expose this capability to scripts via a global `frontier.sqlite` inside the Bun runtime.
- Deliverable: Demo page TypeScript writes to and reads from the SQLite database, with results reflected in the UI.

### Phase 6 — Polishing & Tests
- Add integration tests in Zig that spin up the app headlessly (if possible) to validate navigation and Bun IPC.
- Add Bun tests verifying the RPC contract and SQLite access.
- Wire everything into `just ci` (Zig tests + Bun tests + optional Rust unit tests for the Blitz wrapper).
- Document usage in `README.md` and include troubleshooting tips.

## Stretch (Time Permitting)
- Hot reload for TypeScript during development (watch files, auto-run scripts).
- Minimal DOM patching API between Bun and Blitz to avoid full-page reloads.
- Basic history controls (back/forward) and status indicators in the chrome.

## Immediate To-Dos
1. Scaffold `frontier-zig` repo with build files and placeholder README referencing inspiration from `~/code/frontier`.
2. Create a minimal Rust wrapper crate that compiles Blitz as a `cdylib` and exposes a C header for Zig.
3. Prototype the Bun RPC helper that compiles TypeScript and writes to SQLite, with CLI usage independent of the Zig app.

