use std::panic;
use std::sync::{Arc, Mutex, OnceLock};

use anyrender_vello::VelloWindowRenderer;
use blitz_dom::DocumentConfig;
use blitz_html::HtmlDocument;
use blitz_shell::{create_default_event_loop, BlitzApplication, BlitzShellEvent, View, WindowConfig};
use blitz_traits::navigation::{NavigationProvider, NavigationOptions};
use blitz_traits::net::Body;
use tracing_subscriber::EnvFilter;
use winit::application::ApplicationHandler;
use winit::event::{Modifiers, StartCause, WindowEvent};
use winit::event_loop::ActiveEventLoop;
use winit::keyboard::{KeyCode, PhysicalKey};
use winit::window::{WindowAttributes, WindowId};

fn init_tracing() {
    static INIT: OnceLock<()> = OnceLock::new();
    INIT.get_or_init(|| {
        let _ = tracing_subscriber::fmt()
            .with_env_filter(
                EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
            )
            .with_target(false)
            .try_init();
    });
}

pub struct NavigationState {
    current_html: String,
    current_url: String,
    pending_navigation: Option<(String, String)>, // (html, url)
}

impl NavigationState {
    fn new(html: String, url: String) -> Self {
        Self {
            current_html: html,
            current_url: url,
            pending_navigation: None,
        }
    }
}

// Keyboard shortcut IDs (shared with Zig)
const SHORTCUT_CMD_K: u8 = 1;
const SHORTCUT_CMD_R: u8 = 2;

// Zig functions for getting command palette HTML
#[repr(C)]
struct HtmlResult {
    ptr: *const u8,
    len: usize,
}

extern "C" {
    fn frontier_get_command_palette_html() -> HtmlResult;
    fn frontier_free_html(ptr: *const u8, len: usize);
    fn frontier_navigate_to_url(url_ptr: *const u8, url_len: usize) -> HtmlResult;
}

// Allow undefined symbols for dylib (Zig will provide frontier_handle_shortcut)
#[used]
static _ALLOW_UNDEFINED: () = ();

// Navigation provider that calls into Zig
struct FrontierNavigationProvider {
    state: Arc<Mutex<NavigationState>>,
    event_loop_proxy: winit::event_loop::EventLoopProxy<BlitzShellEvent>,
}

impl NavigationProvider for FrontierNavigationProvider {
    fn navigate_to(&self, options: NavigationOptions) {
        // Check if this is a form submission with a URL input
        let url = if let Body::Form(ref form_data) = options.document_resource {
            // Look for a "url" field in the form data
            if let Some(entry) = form_data.iter().find(|e| e.name == "url") {
                let url_string = entry.value.as_ref();
                tracing::info!("Form submitted with URL: {}", url_string);
                url_string.to_string()
            } else {
                options.url.to_string()
            }
        } else {
            options.url.to_string()
        };

        tracing::info!("Navigation requested to: {}", url);

        // Call Zig to fetch the URL and get HTML
        let html_result = unsafe {
            frontier_navigate_to_url(url.as_ptr(), url.len())
        };

        let html_slice = unsafe {
            std::slice::from_raw_parts(html_result.ptr, html_result.len)
        };
        let html = std::str::from_utf8(html_slice)
            .unwrap_or("<html><body><h1>Invalid UTF-8 in navigation response</h1></body></html>")
            .to_owned();

        tracing::info!("Got HTML from Zig navigation ({} bytes)", html.len());

        // Store pending navigation
        {
            let mut state = self.state.lock().unwrap();
            state.pending_navigation = Some((html, url));
        }

        // Wake up the event loop to apply navigation immediately
        // We can't directly request a redraw here, but we can send a Poll event
        // The pending navigation will be applied in the next new_events() call
        // For now, rely on the next event loop iteration
    }
}

pub struct FrontierApplication {
    inner: BlitzApplication<VelloWindowRenderer>,
    keyboard_modifiers: Modifiers,
    state: Arc<Mutex<NavigationState>>,
    last_rendered_url: String,
    nav_provider: Arc<FrontierNavigationProvider>,
}

// No custom events needed - we update documents directly in window_event()

impl FrontierApplication {
    fn new(
        blitz_proxy: winit::event_loop::EventLoopProxy<BlitzShellEvent>,
        state: Arc<Mutex<NavigationState>>,
        nav_provider: Arc<FrontierNavigationProvider>,
    ) -> Self {
        Self {
            inner: BlitzApplication::new(blitz_proxy),
            keyboard_modifiers: Default::default(),
            state,
            last_rendered_url: String::new(),
            nav_provider,
        }
    }

    fn add_window(&mut self, window_config: WindowConfig<VelloWindowRenderer>) {
        self.inner.add_window(window_config);
    }

    fn window_mut(&mut self) -> &mut View<VelloWindowRenderer> {
        self.inner
            .windows
            .values_mut()
            .next()
            .expect("window available")
    }

    fn update_document(&mut self, html: &str, url: &str) {
        let doc = HtmlDocument::from_html(
            html,
            DocumentConfig {
                base_url: Some(url.to_string()),
                navigation_provider: Some(self.nav_provider.clone()),
                ..Default::default()
            },
        );
        self.window_mut().replace_document(Box::new(doc) as _, false);

        // Update state
        let mut state_lock = self.state.lock().unwrap();
        state_lock.current_html = html.to_owned();
        state_lock.current_url = url.to_owned();

        // Track last rendered
        self.last_rendered_url = url.to_owned();
    }

}

impl ApplicationHandler<BlitzShellEvent> for FrontierApplication {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        self.inner.resumed(event_loop);
    }

    fn suspended(&mut self, event_loop: &ActiveEventLoop) {
        self.inner.suspended(event_loop);
    }

    fn new_events(&mut self, event_loop: &ActiveEventLoop, cause: StartCause) {
        // Check for pending navigation and apply it
        let pending = {
            let mut state = self.state.lock().unwrap();
            state.pending_navigation.take()
        };

        if let Some((html, url)) = pending {
            tracing::info!("Applying pending navigation to: {}", url);
            self.update_document(&html, &url);
        }

        self.inner.new_events(event_loop, cause);
    }

    fn window_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        window_id: WindowId,
        event: WindowEvent,
    ) {
        // Track modifier keys BEFORE processing
        if let WindowEvent::ModifiersChanged(new_state) = &event {
            self.keyboard_modifiers = *new_state;
            tracing::info!("Modifiers changed: ctrl={}, super={}",
                new_state.state().control_key(),
                new_state.state().super_key());
        }

        // Intercept keyboard shortcuts BEFORE passing to inner
        // This is critical because BlitzShell consumes keyboard events
        if let WindowEvent::KeyboardInput { event: key_event, .. } = &event {
            tracing::info!("Keyboard input: {:?}, pressed={}", key_event.physical_key, key_event.state.is_pressed());
            let mods = self.keyboard_modifiers.state();

            if key_event.state.is_pressed() && (mods.control_key() || mods.super_key()) {
                match key_event.physical_key {
                    PhysicalKey::Code(KeyCode::KeyK) => {
                        tracing::info!("Cmd+K detected! Calling Zig for command palette HTML");

                        // Call Zig to get the HTML
                        let html_result = unsafe { frontier_get_command_palette_html() };
                        let html_slice = unsafe { std::slice::from_raw_parts(html_result.ptr, html_result.len) };
                        let html = std::str::from_utf8(html_slice).unwrap_or("<html><body>Invalid UTF-8</body></html>");

                        tracing::info!("Got HTML from Zig ({} bytes)", html.len());

                        // Update document directly
                        self.update_document(html, "http://localhost/");

                        // Note: Not freeing since Zig returns static strings for now
                        // unsafe { frontier_free_html(html_result.ptr, html_result.len) };

                        tracing::info!("Command palette toggled, not passing event to BlitzShell");
                        return; // Don't pass to inner - we handled it
                    }
                    PhysicalKey::Code(KeyCode::KeyR) => {
                        tracing::info!("Cmd+R detected (reload not implemented yet)");
                        return;
                    }
                    _ => {}
                }
            }
        }

        // Pass to BlitzApplication
        self.inner.window_event(event_loop, window_id, event);
    }

    fn user_event(&mut self, event_loop: &ActiveEventLoop, event: BlitzShellEvent) {
        // Check for pending navigation before passing to inner handler
        let pending = {
            let mut state = self.state.lock().unwrap();
            state.pending_navigation.take()
        };

        if let Some((html, url)) = pending {
            tracing::info!("Applying pending navigation to: {}", url);
            self.update_document(&html, &url);
        }

        // Pass to inner handler
        self.inner.user_event(event_loop, event);
    }
}

fn run_event_loop(
    html: &str,
    url: &str,
    state: Arc<Mutex<NavigationState>>,
) -> Result<(), winit::error::EventLoopError> {
    let event_loop = create_default_event_loop::<BlitzShellEvent>();
    let proxy = event_loop.create_proxy();

    // Create navigation provider that calls into Zig
    let nav_provider = Arc::new(FrontierNavigationProvider {
        state: state.clone(),
        event_loop_proxy: proxy.clone(),
    });

    let mut application = FrontierApplication::new(proxy, state.clone(), nav_provider.clone());

    let document = HtmlDocument::from_html(
        html,
        DocumentConfig {
            base_url: Some(url.to_string()),
            navigation_provider: Some(nav_provider),
            ..Default::default()
        },
    );

    let renderer = VelloWindowRenderer::new();
    let attrs = WindowAttributes::default().with_title("Frontier Zig Prototype");
    let window = WindowConfig::with_attributes(Box::new(document) as _, renderer, attrs);

    application.add_window(window);

    // Update state
    {
        let mut state_lock = state.lock().unwrap();
        state_lock.current_html = html.to_owned();
        state_lock.current_url = url.to_owned();
    }

    event_loop.run_app(&mut application)
}

#[no_mangle]
pub extern "C" fn frontier_blitz_run_static_html(html_ptr: *const u8, len: usize) -> bool {
    init_tracing();

    if html_ptr.is_null() {
        tracing::error!("frontier_blitz_run_static_html received null pointer");
        return false;
    }

    let html_slice = unsafe { std::slice::from_raw_parts(html_ptr, len) };
    let html_owned = match std::str::from_utf8(html_slice) {
        Ok(content) => content.to_owned(),
        Err(err) => {
            tracing::error!("frontier_blitz_run_static_html received invalid UTF-8: {err}");
            return false;
        }
    };

    let state = Arc::new(Mutex::new(NavigationState::new(
        html_owned.clone(),
        "http://localhost/".to_string(),
    )));

    let result = panic::catch_unwind(move || run_event_loop(&html_owned, "http://localhost/", state));

    match result {
        Ok(Ok(())) => true,
        Ok(Err(err)) => {
            tracing::error!("frontier_blitz_run_static_html failed: {err}");
            false
        }
        Err(panic_payload) => {
            if let Some(msg) = panic_payload.downcast_ref::<&str>() {
                tracing::error!("frontier_blitz_run_static_html panicked: {msg}");
            } else if let Some(msg) = panic_payload.downcast_ref::<String>() {
                tracing::error!("frontier_blitz_run_static_html panicked: {msg}");
            } else {
                tracing::error!("frontier_blitz_run_static_html panicked");
            }
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn frontier_blitz_navigate(
    html_ptr: *const u8,
    html_len: usize,
    url_ptr: *const u8,
    url_len: usize,
) -> bool {
    init_tracing();

    if html_ptr.is_null() || url_ptr.is_null() {
        tracing::error!("frontier_blitz_navigate received null pointer");
        return false;
    }

    let html_slice = unsafe { std::slice::from_raw_parts(html_ptr, html_len) };
    let html_owned = match std::str::from_utf8(html_slice) {
        Ok(content) => content.to_owned(),
        Err(err) => {
            tracing::error!("frontier_blitz_navigate received invalid HTML UTF-8: {err}");
            return false;
        }
    };

    let url_slice = unsafe { std::slice::from_raw_parts(url_ptr, url_len) };
    let url_owned = match std::str::from_utf8(url_slice) {
        Ok(content) => content.to_owned(),
        Err(err) => {
            tracing::error!("frontier_blitz_navigate received invalid URL UTF-8: {err}");
            return false;
        }
    };

    tracing::info!("Navigating to: {}", url_owned);

    let state = Arc::new(Mutex::new(NavigationState::new(
        html_owned.clone(),
        url_owned.clone(),
    )));

    let result = panic::catch_unwind(move || run_event_loop(&html_owned, &url_owned, state));

    match result {
        Ok(Ok(())) => true,
        Ok(Err(err)) => {
            tracing::error!("frontier_blitz_navigate failed: {err}");
            false
        }
        Err(panic_payload) => {
            if let Some(msg) = panic_payload.downcast_ref::<&str>() {
                tracing::error!("frontier_blitz_navigate panicked: {msg}");
            } else if let Some(msg) = panic_payload.downcast_ref::<String>() {
                tracing::error!("frontier_blitz_navigate panicked: {msg}");
            } else {
                tracing::error!("frontier_blitz_navigate panicked");
            }
            false
        }
    }
}

// No global state needed - everything happens in window_event()
