/// Minimal demo of modal overlay with Cmd+K toggle
use anyrender_vello::VelloWindowRenderer;
use blitz_dom::DocumentConfig;
use blitz_html::HtmlDocument;
use blitz_shell::{create_default_event_loop, BlitzApplication, BlitzShellEvent, WindowConfig};
use winit::application::ApplicationHandler;
use winit::event::{Modifiers, StartCause, WindowEvent};
use winit::event_loop::ActiveEventLoop;
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::WindowAttributes;

struct ModalApp {
    inner: BlitzApplication<VelloWindowRenderer>,
    keyboard_modifiers: Modifiers,
    modal_visible: bool,
}

impl ModalApp {
    fn new(proxy: winit::event_loop::EventLoopProxy<BlitzShellEvent>) -> Self {
        Self {
            inner: BlitzApplication::new(proxy),
            keyboard_modifiers: Default::default(),
            modal_visible: false,
        }
    }

    fn update_html(&mut self) {
        if self.inner.windows.is_empty() {
            println!("No windows yet, skipping update");
            return;
        }

        let html = if self.modal_visible {
            // Page WITH modal overlay
            r#"<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>Modal Demo</title>
    <style>
        body { margin: 0; font-family: sans-serif; }
        .page-content {
            padding: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
        }
        .cmd-palette-backdrop {
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(0, 0, 0, 0.5);
            z-index: 9999;
            display: flex;
            align-items: flex-start;
            justify-content: center;
            padding-top: 20vh;
        }
        .cmd-palette-modal {
            background: white;
            border-radius: 8px;
            box-shadow: 0 25px 50px rgba(0, 0, 0, 0.5);
            width: 90%;
            max-width: 600px;
            padding: 24px;
            color: #333;
        }
        .cmd-palette-modal h1 { margin: 0 0 16px 0; }
        .cmd-palette-modal input {
            width: 100%;
            padding: 12px;
            font-size: 16px;
            border: 2px solid #ddd;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <div class="page-content">
        <h1>🎨 Base Page Content</h1>
        <p>This is the underlying page. Press Cmd+K to show/hide modal.</p>
        <p>You should see this content BEHIND the modal when it's visible.</p>
    </div>
    <div class="cmd-palette-backdrop">
        <div class="cmd-palette-modal">
            <h1>🚀 Modal Overlay</h1>
            <input type="text" placeholder="Type here..." autofocus />
            <p>Press Cmd+K to close</p>
        </div>
    </div>
</body>
</html>"#
        } else {
            // Page WITHOUT modal
            r#"<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>Modal Demo</title>
    <style>
        body { margin: 0; font-family: sans-serif; }
        .page-content {
            padding: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
        }
    </style>
</head>
<body>
    <div class="page-content">
        <h1>🎨 Base Page Content</h1>
        <p>This is the underlying page. Press Cmd+K to show/hide modal.</p>
        <p>Modal is currently HIDDEN.</p>
    </div>
</body>
</html>"#
        };

        let doc = HtmlDocument::from_html(html, DocumentConfig::default());
        let view = self.inner.windows.values_mut().next().expect("window");
        view.replace_document(Box::new(doc) as _, false);

        println!("Updated HTML - modal_visible: {}", self.modal_visible);
    }
}

impl ApplicationHandler<BlitzShellEvent> for ModalApp {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        self.inner.resumed(event_loop);
        self.update_html(); // Set initial HTML when window is ready
    }

    fn suspended(&mut self, event_loop: &ActiveEventLoop) {
        self.inner.suspended(event_loop);
    }

    fn new_events(&mut self, event_loop: &ActiveEventLoop, cause: StartCause) {
        self.inner.new_events(event_loop, cause);
    }

    fn window_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        window_id: winit::window::WindowId,
        event: WindowEvent,
    ) {
        if let WindowEvent::ModifiersChanged(new_state) = &event {
            self.keyboard_modifiers = *new_state;
        }

        if let WindowEvent::KeyboardInput { event: key_event, .. } = &event {
            let mods = self.keyboard_modifiers.state();
            if key_event.state.is_pressed()
                && (mods.control_key() || mods.super_key())
                && matches!(key_event.physical_key, PhysicalKey::Code(KeyCode::KeyK))
            {
                println!("Cmd+K detected!");
                self.modal_visible = !self.modal_visible;
                self.update_html();
                return; // Don't pass to inner
            }
        }

        self.inner.window_event(event_loop, window_id, event);
    }

    fn user_event(&mut self, event_loop: &ActiveEventLoop, event: BlitzShellEvent) {
        self.inner.user_event(event_loop, event);
    }
}

fn main() {
    let event_loop = create_default_event_loop::<BlitzShellEvent>();
    let proxy = event_loop.create_proxy();

    let mut app = ModalApp::new(proxy);

    let doc = HtmlDocument::from_html(
        r#"<!DOCTYPE html><html><body><h1>Loading...</h1></body></html>"#,
        DocumentConfig::default(),
    );
    let renderer = VelloWindowRenderer::new();
    let attrs = WindowAttributes::default().with_title("Modal Demo");
    let window = WindowConfig::with_attributes(Box::new(doc) as _, renderer, attrs);

    app.inner.add_window(window);

    println!("Modal Demo - Press Cmd+K to toggle modal overlay");
    event_loop.run_app(&mut app).unwrap();
}
