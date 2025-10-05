const std = @import("std");

extern fn frontier_blitz_run_static_html(html_ptr: [*]const u8, len: usize) callconv(.c) bool;

const DEMO_HTML =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\  <head>
    \\    <meta charset="utf-8" />
    \\    <title>Frontier Zig Prototype</title>
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
    \\    </style>
    \\  </head>
    \\  <body>
    \\    <main>
    \\      <header>
    \\        <p class="badge" style="position: absolute; top: 32px; right: 32px; width: auto; border-radius: 999px; padding: 6px 16px; box-shadow: none;">Phase 1</p>
    \\        <h1>Frontier Zig + Blitz</h1>
    \\        <p>
    \\          This window is rendered by Blitz through the Rust bridge, launched from the Zig host.
    \\        </p>
    \\      </header>
    \\      <section class="card">
    \\        <h2 style="margin-top: 0; font-size: 22px;">Phase 1 Deliverables</h2>
    \\        <div class="steps">
    \\          <div class="step">
    \\            <span class="badge">1</span>
    \\            <div>
    \\              <strong>Winit + Blitz window</strong>
    \\              <p>The window and event loop are hosted by Rust's Blitz shell and called from Zig.</p>
    \\            </div>
    \\          </div>
    \\          <div class="step">
    \\            <span class="badge">2</span>
    \\            <div>
    \\              <strong>Static HTML</strong>
    \\              <p>The content you are reading was provided as an inline HTML string from the Zig executable.</p>
    \\            </div>
    \\          </div>
    \\          <div class="step">
    \\            <span class="badge">3</span>
    \\            <div>
    \\              <strong>Future phases</strong>
    \\              <p>Next up: navigation, Bun RPC, TypeScript execution, and SQLite integrations.</p>
    \\            </div>
    \\          </div>
    \\        </div>
    \\      </section>
    \\      <footer>
    \\        <p>Launch command: <code>just run</code></p>
    \\      </footer>
    \\    </main>
    \\  </body>
    \\</html>
;

pub fn main() !void {
    std.log.info("Launching Blitz renderer prototype", .{});

    const ok = frontier_blitz_run_static_html(DEMO_HTML.ptr, DEMO_HTML.len);
    if (!ok) {
        std.log.err("Blitz bridge reported a failure—see Rust-side logs for details", .{});
        return error.BlitzBridgeFailed;
    }
}

test "builtin sanity" {
    try std.testing.expectEqual(@as(u8, 1), 1);
}
