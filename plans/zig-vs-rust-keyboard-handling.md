# Zig vs Rust: Keyboard Event Handling Analysis

## The Question

Should keyboard event handling (Cmd+K) be implemented in Zig or Rust?

**Goal:** Keep business logic in Zig to the maximum extent possible.

## Current Architecture

### Rust Bridge (Current)
```rust
// rust/src/lib.rs
#[no_mangle]
pub extern "C" fn frontier_blitz_run_static_html(html_ptr: *const u8, len: usize) -> bool {
    // ...
    let mut application = BlitzApplication::new(proxy);
    // ...
    event_loop.run_app(&mut application)  // ← Takes control, never returns
}
```

**Problem:** `event_loop.run_app()` takes complete control and never returns to Zig. The event loop runs entirely in Rust.

### Zig Side (Current)
```zig
// zig/src/main.zig
pub fn main() !void {
    // Parse command line args
    // Fetch HTML

    const ok = frontier_blitz_run_static_html(html.ptr, html.len);
    // ← This call NEVER RETURNS until window closes
}
```

## Option 1: Implement in Rust (Event Loop Lives There)

### Architecture

```rust
// rust/src/lib.rs

pub struct FrontierApplication {
    inner: BlitzApplication<WindowRenderer>,
    keyboard_modifiers: Modifiers,
    command_palette_visible: bool,

    // Callback to Zig for business logic
    on_cmd_k_callback: Option<extern "C" fn() -> bool>,
}

impl ApplicationHandler<BlitzShellEvent> for FrontierApplication {
    fn window_event(&mut self, ..., event: WindowEvent) {
        if let WindowEvent::ModifiersChanged(new_state) = &event {
            self.keyboard_modifiers = *new_state;
        }

        if let WindowEvent::KeyboardInput { event, .. } = &event {
            let mods = self.keyboard_modifiers.state();
            if event.state.is_pressed() && (mods.control_key() || mods.super_key()) {
                if let PhysicalKey::Code(KeyCode::KeyK) = event.physical_key {
                    // Call back to Zig for business logic
                    if let Some(callback) = self.on_cmd_k_callback {
                        callback();
                    }
                    return;
                }
            }
        }

        self.inner.window_event(..., event);
    }
}

#[no_mangle]
pub extern "C" fn frontier_blitz_set_cmd_k_handler(
    callback: extern "C" fn() -> bool
) {
    // Store callback for later use
}
```

### Pros
✅ Event loop already runs in Rust (winit requirement)
✅ Direct access to winit types (Modifiers, KeyCode, etc.)
✅ No FFI overhead for every keyboard event
✅ Matches frontier architecture (which is pure Rust)
✅ Can handle keyboard events immediately without crossing FFI boundary

### Cons
❌ Business logic split between Zig and Rust
❌ Callbacks from Rust → Zig are awkward
❌ State management becomes complex (who owns what?)
❌ Rust owns the event loop = Rust owns the app lifecycle

## Option 2: Implement in Zig (Callback-Based)

### Architecture

```zig
// zig/src/main.zig

// Callback from Rust event loop
export fn frontier_on_keyboard_event(
    key_code: u32,
    is_super_pressed: bool,
    is_ctrl_pressed: bool,
    is_pressed: bool,
) void {
    // Business logic in Zig!
    if (is_pressed and (is_super_pressed or is_ctrl_pressed)) {
        if (key_code == KEY_K) {
            toggleCommandPalette();
        }
    }
}

fn toggleCommandPalette() void {
    command_palette_visible = !command_palette_visible;

    const html = if (command_palette_visible)
        command_palette.generateCommandPaletteHtml(...)
    else
        current_document_html;

    // Update Rust side
    frontier_blitz_update_html(html.ptr, html.len);
}
```

```rust
// rust/src/lib.rs

// Declare Zig callback
extern "C" {
    fn frontier_on_keyboard_event(
        key_code: u32,
        is_super_pressed: bool,
        is_ctrl_pressed: bool,
        is_pressed: bool,
    );
}

impl ApplicationHandler<BlitzShellEvent> for FrontierApplication {
    fn window_event(&mut self, ..., event: WindowEvent) {
        if let WindowEvent::ModifiersChanged(new_state) = &event {
            self.keyboard_modifiers = *new_state;
        }

        if let WindowEvent::KeyboardInput { event, .. } = &event {
            // Forward to Zig
            let key_code = match event.physical_key {
                PhysicalKey::Code(code) => code as u32,
                _ => return,
            };

            unsafe {
                frontier_on_keyboard_event(
                    key_code,
                    self.keyboard_modifiers.state().super_key(),
                    self.keyboard_modifiers.state().control_key(),
                    event.state.is_pressed(),
                );
            }
            return;
        }

        self.inner.window_event(..., event);
    }
}

// New C ABI for updating HTML from Zig
#[no_mangle]
pub extern "C" fn frontier_blitz_update_html(html_ptr: *const u8, len: usize) {
    // Update the document without restarting event loop
}
```

### Pros
✅ Business logic stays in Zig ⭐
✅ Zig controls navigation state, command palette visibility, etc.
✅ Simpler mental model: Rust is just a "renderer service"
✅ Aligns with stated goal of keeping logic in Zig

### Cons
❌ FFI boundary crossed for every keyboard event
❌ Need to translate winit types to C-compatible types
❌ Requires `frontier_blitz_update_html()` - updating document without restarting event loop is complex
❌ State synchronization between Zig and Rust becomes critical

## Option 3: Hybrid (Recommended)

### Architecture

**Principle:** Rust handles low-level event routing, Zig handles business logic.

```rust
// rust/src/lib.rs

// Simple callback interface
extern "C" {
    fn frontier_handle_shortcut(shortcut_id: u8) -> bool;
}

const SHORTCUT_CMD_K: u8 = 1;
const SHORTCUT_CMD_R: u8 = 2;
// ... more shortcuts

impl ApplicationHandler<BlitzShellEvent> for FrontierApplication {
    fn window_event(&mut self, ..., event: WindowEvent) {
        if let WindowEvent::ModifiersChanged(new_state) = &event {
            self.keyboard_modifiers = *new_state;
        }

        if let WindowEvent::KeyboardInput { event, .. } = &event {
            let mods = self.keyboard_modifiers.state();
            if event.state.is_pressed() && (mods.control_key() || mods.super_key()) {
                let shortcut = match event.physical_key {
                    PhysicalKey::Code(KeyCode::KeyK) => Some(SHORTCUT_CMD_K),
                    PhysicalKey::Code(KeyCode::KeyR) => Some(SHORTCUT_CMD_R),
                    _ => None,
                };

                if let Some(id) = shortcut {
                    let handled = unsafe { frontier_handle_shortcut(id) };
                    if handled {
                        return; // Don't pass to inner
                    }
                }
            }
        }

        self.inner.window_event(..., event);
    }
}
```

```zig
// zig/src/main.zig

const SHORTCUT_CMD_K: u8 = 1;
const SHORTCUT_CMD_R: u8 = 2;

export fn frontier_handle_shortcut(shortcut_id: u8) bool {
    switch (shortcut_id) {
        SHORTCUT_CMD_K => {
            toggleCommandPalette();
            return true;
        },
        SHORTCUT_CMD_R => {
            reloadCurrentPage();
            return true;
        },
        else => return false,
    }
}

fn toggleCommandPalette() void {
    // All business logic here!
    command_palette_visible = !command_palette_visible;

    const html = if (command_palette_visible)
        command_palette.generateCommandPaletteHtml(allocator, current_url)
    else
        navigation_history.currentDocument();

    _ = frontier_blitz_update_document(html.ptr, html.len);
}
```

### Pros
✅ Business logic stays in Zig ⭐⭐
✅ Minimal FFI overhead (only when shortcut detected, not every keystroke)
✅ Clean separation: Rust = event detection, Zig = business logic
✅ Easy to add new shortcuts (just add to enum)
✅ Type-safe with simple u8 enum across FFI
✅ Zig can return `false` to let Rust handle shortcut if needed

### Cons
❌ Still need `frontier_blitz_update_document()` function
❌ Two layers of event handling (Rust detects, Zig handles)

## Recommendation: **Option 3 (Hybrid)**

### Rationale

1. **Aligns with goal:** Business logic stays in Zig
2. **Pragmatic:** Rust is better suited for winit event loop (it's a Rust library)
3. **Clean separation:** Rust is a "platform layer", Zig is the "application layer"
4. **Extensible:** Easy to add shortcuts without touching Rust
5. **Performance:** Minimal FFI overhead (only on detected shortcuts)

### Implementation Priority

1. **First:** Implement `frontier_blitz_update_document()` in Rust
   - This allows updating HTML without restarting event loop
   - Critical for command palette toggle

2. **Second:** Create `FrontierApplication` wrapper in Rust
   - Implement keyboard shortcut detection
   - Call Zig callback with simple enum

3. **Third:** Implement business logic in Zig
   - `frontier_handle_shortcut()` callback
   - Command palette toggle logic
   - Navigation state management

## Comparison to Frontier

Frontier is **pure Rust** - all business logic is in Rust:
```rust
// ~/code/frontier/src/readme_application.rs
impl ApplicationHandler<BlitzShellEvent> for ReadmeApplication {
    fn window_event(...) {
        // All logic here - no callbacks to other languages
    }
}
```

**Our approach:** Rust is the renderer, Zig is the application.

This is the **right** architecture for frontier-zig because:
- Zig is our primary language (by design)
- Rust is just the bridge to Blitz
- Future phases will add more Zig logic (Bun integration, SQLite, etc.)
