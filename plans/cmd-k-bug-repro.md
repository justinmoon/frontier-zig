# Cmd+K Keyboard Shortcut Bug - Reproduction & Root Cause

## Reproduction Steps

1. **Build and run the application:**
   ```bash
   just run
   ```

2. **Wait for the window to open** showing the Frontier Zig Navigator interface

3. **Press Cmd+K** (on macOS) or **Ctrl+K** (on Linux/Windows)

4. **Observe:**
   - **Expected:** Command palette overlay appears
   - **Actual:** Nothing happens ❌

## Root Cause Analysis

### Current Architecture

The Rust bridge in `rust/src/lib.rs` creates a simple event loop without custom keyboard handling:

```rust
fn run_event_loop(html: &str, url: &str, state: Arc<Mutex<NavigationState>>)
    -> Result<(), winit::error::EventLoopError>
{
    let event_loop = create_default_event_loop::<BlitzShellEvent>();
    let proxy = event_loop.create_proxy();

    let mut application = BlitzApplication::new(proxy);
    // ... configure window ...

    event_loop.run_app(&mut application)  // BlitzApplication handles all events
}
```

**Problem:** `BlitzApplication` handles all window events, but we never intercept them to check for keyboard shortcuts like Cmd+K.

### What's Missing

We need a custom `ApplicationHandler` implementation that:

1. **Wraps `BlitzApplication`** instead of using it directly
2. **Tracks keyboard modifiers** (Cmd/Ctrl key state)
3. **Intercepts keyboard events** before passing them to BlitzApplication
4. **Checks for Cmd+K** and toggles command palette when detected

### Reference Implementation

See `~/code/frontier/src/readme_application.rs:418-476` for a working example:

```rust
impl ApplicationHandler<BlitzShellEvent> for ReadmeApplication {
    fn window_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        window_id: WindowId,
        event: WindowEvent,
    ) {
        // Track modifier keys (Cmd/Ctrl)
        if let WindowEvent::ModifiersChanged(new_state) = &event {
            self.keyboard_modifiers = *new_state;
        }

        // Intercept keyboard input
        if let WindowEvent::KeyboardInput { event, .. } = &event {
            let mods = self.keyboard_modifiers.state();
            if !event.state.is_pressed() && (mods.control_key() || mods.super_key()) {
                match event.physical_key {
                    PhysicalKey::Code(KeyCode::KeyR) => self.reload_document(true),
                    PhysicalKey::Code(KeyCode::KeyT) => self.toggle_theme(),
                    PhysicalKey::Code(KeyCode::KeyB) => { /* back navigation */ }
                    _ => {}
                }
            }
        }

        // Pass remaining events to BlitzApplication
        self.inner.window_event(event_loop, window_id, event);
    }
}
```

## Required Changes

### 1. Create Custom Application Handler

**File:** `rust/src/lib.rs`

```rust
use winit::event::{Modifiers, WindowEvent};
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::application::ApplicationHandler;
use winit::window::WindowId;
use winit::event_loop::ActiveEventLoop;

pub struct FrontierApplication {
    inner: BlitzApplication<WindowRenderer>,
    keyboard_modifiers: Modifiers,
    command_palette_visible: bool,
    current_state: Arc<Mutex<NavigationState>>,
}

impl ApplicationHandler<BlitzShellEvent> for FrontierApplication {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        self.inner.resumed(event_loop);
    }

    fn suspended(&mut self, event_loop: &ActiveEventLoop) {
        self.inner.suspended(event_loop);
    }

    fn window_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        window_id: WindowId,
        event: WindowEvent,
    ) {
        // Track modifiers
        if let WindowEvent::ModifiersChanged(new_state) = &event {
            self.keyboard_modifiers = *new_state;
        }

        // Handle keyboard shortcuts
        if let WindowEvent::KeyboardInput { event, .. } = &event {
            let mods = self.keyboard_modifiers.state();
            if event.state.is_pressed() && (mods.control_key() || mods.super_key()) {
                if let PhysicalKey::Code(KeyCode::KeyK) = event.physical_key {
                    self.toggle_command_palette();
                    return; // Don't pass to inner
                }
            }
        }

        // Pass other events to BlitzApplication
        self.inner.window_event(event_loop, window_id, event);
    }

    fn user_event(&mut self, event_loop: &ActiveEventLoop, event: BlitzShellEvent) {
        self.inner.user_event(event_loop, event);
    }
}
```

### 2. Implement Command Palette Toggle

```rust
impl FrontierApplication {
    fn toggle_command_palette(&mut self) {
        self.command_palette_visible = !self.command_palette_visible;

        // Generate command palette HTML
        let html = if self.command_palette_visible {
            generate_command_palette_overlay()
        } else {
            // Return to previous content
            let state = self.current_state.lock().unwrap();
            state.current_html.clone()
        };

        // Update window with new HTML
        let doc = HtmlDocument::from_html(&html, /* ... */);
        self.window_mut().replace_document(Box::new(doc) as _, false);
    }
}
```

### 3. Update Event Loop Function

```rust
fn run_event_loop(
    html: &str,
    url: &str,
    state: Arc<Mutex<NavigationState>>
) -> Result<(), winit::error::EventLoopError> {
    let event_loop = create_default_event_loop::<BlitzShellEvent>();
    let proxy = event_loop.create_proxy();

    let mut application = FrontierApplication {
        inner: BlitzApplication::new(proxy),
        keyboard_modifiers: Default::default(),
        command_palette_visible: false,
        current_state: state.clone(),
    };

    // ... configure window ...

    event_loop.run_app(&mut application)
}
```

## Test Verification

Run the test suite to verify the issue:

```bash
cd rust
cargo test keyboard -- --include-ignored
```

Tests include:
- `test_cmd_k_triggers_command_palette` - Documents expected behavior
- `test_missing_keyboard_handler` - Documents architecture changes needed
- `manual_test_keyboard_events` - Manual testing procedure

## Phase 2 Note

The plan specified a "command palette (e.g. shift-command-p in vscode etc)" but noted:
> "Kind of a PITA. I want this to be simpler."

**Current Status:** Phase 2 focused on navigation infrastructure without JavaScript. The interactive Cmd+K command palette requires:
- Custom keyboard event handling (this bug)
- JavaScript for interactive UI (Phase 3-4)

**Interim Solution:** The current command-line based navigator (using `just run -- <url>`) works for Phase 2 testing.

**Phase 3 Plan:** Implement proper keyboard event handling when adding Bun/TypeScript integration, allowing for a fully interactive command palette.
