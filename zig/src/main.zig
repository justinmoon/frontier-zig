const std = @import("std");
const navigation = @import("navigation.zig");
const command_palette = @import("command_palette.zig");
const shortcuts = @import("shortcuts.zig");

extern fn frontier_blitz_run_static_html(html_ptr: [*]const u8, len: usize) callconv(.c) bool;
extern fn frontier_blitz_navigate(html_ptr: [*]const u8, html_len: usize, url_ptr: [*]const u8, url_len: usize) callconv(.c) bool;
extern fn frontier_blitz_update_document(html_ptr: [*]const u8, html_len: usize, url_ptr: [*]const u8, url_len: usize) callconv(.c) bool;

const DEMO_HTML =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\  <head>
    \\    <meta charset="utf-8" />
    \\    <title>Frontier Zig Prototype - Phase 2</title>
    \\    <style>
    \\      * { box-sizing: border-box; }
    \\      html, body {
    \\        margin: 0;
    \\        padding: 0;
    \\        width: 100%;
    \\        height: 100%;
    \\        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    \\        background: linear-gradient(180deg, #f3f4f6 0%, #ffffff 60%);
    \\        color: #0f172a;
    \\      }
    \\      main {
    \\        display: flex;
    \\        flex-direction: column;
    \\        gap: 16px;
    \\        max-width: 720px;
    \\        margin: 0 auto;
    \\        padding: 48px 32px;
    \\      }
    \\      h1 {
    \\        font-size: 32px;
    \\        margin: 0;
    \\      }
    \\      p {
    \\        line-height: 1.6;
    \\        margin: 0;
    \\      }
    \\      .card {
    \\        background: rgba(255, 255, 255, 0.85);
    \\        border-radius: 16px;
    \\        padding: 24px;
    \\        box-shadow: 0 20px 45px rgba(15, 23, 42, 0.08);
    \\        border: 1px solid rgba(148, 163, 184, 0.18);
    \\      }
    \\      .steps {
    \\        display: grid;
    \\        gap: 12px;
    \\      }
    \\      .step {
    \\        display: flex;
    \\        gap: 12px;
    \\        align-items: flex-start;
    \\      }
    \\      .badge {
    \\        width: 28px;
    \\        height: 28px;
    \\        border-radius: 50%;
    \\        background: #0ea5e9;
    \\        color: #fff;
    \\        font-weight: 600;
    \\        display: flex;
    \\        align-items: center;
    \\        justify-content: center;
    \\        box-shadow: 0 10px 24px rgba(14, 165, 233, 0.35);
    \\      }
    \\      footer {
    \\        margin-top: 24px;
    \\        font-size: 14px;
    \\        color: #475569;
    \\      }
    \\      code {
    \\        font-family: SFMono-Regular, ui-monospace, Menlo, Consolas, monospace;
    \\        padding: 2px 6px;
    \\        border-radius: 6px;
    \\        background: rgba(15, 23, 42, 0.1);
    \\      }
    \\      .kbd {
    \\        display: inline-block;
    \\        padding: 3px 7px;
    \\        font-family: SFMono-Regular, ui-monospace, Menlo, Consolas, monospace;
    \\        font-size: 12px;
    \\        background: #f8fafc;
    \\        border: 1px solid #cbd5e1;
    \\        border-radius: 4px;
    \\        box-shadow: 0 2px 0 #cbd5e1;
    \\      }
    \\      .navigation-demo {
    \\        margin-top: 16px;
    \\      }
    \\      .url-example {
    \\        background: #f1f5f9;
    \\        padding: 12px;
    \\        border-radius: 8px;
    \\        font-family: monospace;
    \\        font-size: 13px;
    \\        margin: 8px 0;
    \\      }
    \\    </style>
    \\  </head>
    \\  <body>
    \\    <main>
    \\      <header>
    \\        <p class="badge" style="position: absolute; top: 32px; right: 32px; width: auto; border-radius: 999px; padding: 6px 16px; box-shadow: none;">Phase 2</p>
    \\        <h1>Frontier Zig + Blitz</h1>
    \\        <p>
    \\          Navigation and address bar features are now available!
    \\        </p>
    \\      </header>
    \\      <section class="card">
    \\        <h2 style="margin-top: 0; font-size: 22px;">Phase 2 Deliverables</h2>
    \\        <div class="steps">
    \\          <div class="step">
    \\            <span class="badge">1</span>
    \\            <div>
    \\              <strong>URL Parsing & Fetching</strong>
    \\              <p>Support for HTTP, HTTPS, and file:// URLs with complete parsing and navigation history.</p>
    \\            </div>
    \\          </div>
    \\          <div class="step">
    \\            <span class="badge">2</span>
    \\            <div>
    \\              <strong>Command Palette Navigation</strong>
    \\              <p>Press <span class="kbd">Cmd+K</span> to open the command palette for URL navigation.</p>
    \\            </div>
    \\          </div>
    \\          <div class="step">
    \\            <span class="badge">3</span>
    \\            <div>
    \\              <strong>Navigation History</strong>
    \\              <p>Back/forward navigation with <span class="kbd">Cmd+[</span> and <span class="kbd">Cmd+]</span>.</p>
    \\            </div>
    \\          </div>
    \\        </div>
    \\        <div class="navigation-demo">
    \\          <h3 style="font-size: 16px; margin-bottom: 8px;">Try navigating to:</h3>
    \\          <div class="url-example">https://example.com</div>
    \\          <div class="url-example">file:///path/to/local/file.html</div>
    \\        </div>
    \\      </section>
    \\      <footer>
    \\        <p>Launch command: <code>just run</code></p>
    \\        <p style="margin-top: 8px;">Next up: Bun RPC, TypeScript execution, and SQLite integration.</p>
    \\      </footer>
    \\    </main>
    \\  </body>
    \\</html>
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command-line arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip executable name
    _ = args.next();

    const url = args.next();

    if (url) |target_url| {
        // User provided a URL on command line
        std.log.info("Launching Blitz with URL: {s}", .{target_url});

        // Initialize shortcuts with the URL
        shortcuts.init(target_url);

        const html_content = navigation.fetchUrl(allocator, target_url) catch |err| {
            std.log.err("Failed to fetch URL {s}: {}", .{ target_url, err });
            return err;
        };
        defer allocator.free(html_content);

        // Save the content for command palette toggle
        try shortcuts.saveCurrentDocument(html_content);

        const ok = frontier_blitz_navigate(
            html_content.ptr,
            html_content.len,
            target_url.ptr,
            target_url.len,
        );

        if (!ok) {
            std.log.err("Blitz bridge reported a failure—see Rust-side logs for details", .{});
            return error.BlitzBridgeFailed;
        }
    } else {
        // No URL provided, show command palette navigator
        std.log.info("Launching Frontier Zig Navigator (Phase 2)", .{});

        // Initialize shortcuts
        shortcuts.init(null);

        const palette_html = try command_palette.generateCommandPaletteHtml(allocator, null);
        defer allocator.free(palette_html);

        const ok = frontier_blitz_run_static_html(palette_html.ptr, palette_html.len);
        if (!ok) {
            std.log.err("Blitz bridge reported a failure—see Rust-side logs for details", .{});
            return error.BlitzBridgeFailed;
        }
    }
}

test "builtin sanity" {
    try std.testing.expectEqual(@as(u8, 1), 1);
}
