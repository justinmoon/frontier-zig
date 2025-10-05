use std::panic;
use std::sync::OnceLock;

use anyrender_vello::VelloWindowRenderer;
use blitz_dom::DocumentConfig;
use blitz_html::HtmlDocument;
use blitz_shell::{create_default_event_loop, BlitzApplication, BlitzShellEvent, WindowConfig};
use tracing_subscriber::EnvFilter;
use winit::window::WindowAttributes;

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

fn run_event_loop(html: &str) -> Result<(), winit::error::EventLoopError> {
    let event_loop = create_default_event_loop::<BlitzShellEvent>();
    let proxy = event_loop.create_proxy();

    let mut application = BlitzApplication::new(proxy);

    let document = HtmlDocument::from_html(
        html,
        DocumentConfig {
            base_url: Some(String::from("about:blank")),
            ..Default::default()
        },
    );

    let renderer = VelloWindowRenderer::new();
    let attrs = WindowAttributes::default().with_title("Frontier Zig Prototype");
    let window = WindowConfig::with_attributes(Box::new(document) as _, renderer, attrs);

    application.add_window(window);

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

    let result = panic::catch_unwind(move || run_event_loop(&html_owned));

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
