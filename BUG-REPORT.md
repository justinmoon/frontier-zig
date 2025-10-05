# Bug Report: Cmd+K Does Nothing

## Summary

Pressing Cmd+K (or Ctrl+K) does not trigger the command palette as intended.

## Reproduction

### Automated Test

```bash
cargo test --manifest-path rust/Cargo.toml test_cmd_k_triggers_command_palette -- --include-ignored
```

**Result:**
```
thread 'test_cmd_k_triggers_command_palette' panicked at tests/keyboard_test.rs:68:5:
Cmd+K keyboard shortcut not implemented. See readme_application.rs:418-476 in ~/code/frontier for reference implementation.
```

### Manual Test

1. Run the application:
   ```bash
   just run
   ```

2. When the window opens, press **Cmd+K** (macOS) or **Ctrl+K** (Linux/Windows)

3. **Expected:** Command palette overlay appears
4. **Actual:** Nothing happens ❌

## Root Cause

The Rust bridge (`rust/src/lib.rs`) does not implement custom keyboard event handling. It directly uses `BlitzApplication` which handles window events but doesn't intercept keyboard shortcuts.

### Current Architecture (Broken)

```rust
fn run_event_loop(...) {
    let event_loop = create_default_event_loop::<BlitzShellEvent>();
    let mut application = BlitzApplication::new(proxy);
    // ...
    event_loop.run_app(&mut application)  // ← No keyboard interception
}
```

### Required Architecture (Working)

We need a custom `ApplicationHandler` that wraps `BlitzApplication`:

```rust
struct FrontierApplication {
    inner: BlitzApplication<...>,
    keyboard_modifiers: Modifiers,
    // ...
}

impl ApplicationHandler<BlitzShellEvent> for FrontierApplication {
    fn window_event(&mut self, ..., event: WindowEvent) {
        // Track modifiers
        if let WindowEvent::ModifiersChanged(new_state) = &event {
            self.keyboard_modifiers = *new_state;
        }

        // Intercept keyboard shortcuts
        if let WindowEvent::KeyboardInput { event, .. } = &event {
            let mods = self.keyboard_modifiers.state();
            if event.state.is_pressed() && (mods.control_key() || mods.super_key()) {
                if let PhysicalKey::Code(KeyCode::KeyK) = event.physical_key {
                    self.toggle_command_palette();
                    return;  // ← Intercept and handle
                }
            }
        }

        // Pass other events through
        self.inner.window_event(..., event);
    }
}
```

## Reference Implementation

See `~/code/frontier/src/readme_application.rs:418-476` for a complete working example of keyboard event handling with similar shortcuts:
- Cmd+R: Reload
- Cmd+T: Toggle theme
- Cmd+B: Go back

## Test Files

- **Automated test:** `rust/tests/keyboard_test.rs`
  - `test_keyboard_shortcut_structure` - Verifies DOM structure ✅
  - `test_cmd_k_triggers_command_palette` - Reproduces the bug ❌
  - `test_missing_keyboard_handler` - Documents architecture fix needed
  - `manual_test_keyboard_events` - Manual testing procedure

- **Documentation:** `plans/cmd-k-bug-repro.md`
  - Detailed reproduction steps
  - Architecture analysis
  - Complete code fix examples

## Next Steps

To fix this issue:

1. Create `FrontierApplication` struct in `rust/src/lib.rs` that wraps `BlitzApplication`
2. Implement `ApplicationHandler<BlitzShellEvent>` for `FrontierApplication`
3. Add keyboard modifier tracking
4. Intercept `WindowEvent::KeyboardInput` and check for Cmd+K
5. Implement `toggle_command_palette()` method
6. Update event loop to use `FrontierApplication` instead of `BlitzApplication` directly

## Phase Context

This aligns with Phase 2 goals but was scoped out of the initial implementation. The plan noted that a full interactive command palette (like VS Code's Cmd+Shift+P) would be "kind of a PITA" and suggested a simpler approach.

**Current workaround:** Use command-line navigation: `just run -- <url>`

**Planned for Phase 3:** Full keyboard event handling when implementing Bun/TypeScript integration for interactive UI.
