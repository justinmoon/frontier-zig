const std = @import("std");

pub fn generateCommandPaletteHtml(allocator: std.mem.Allocator, current_url: ?[]const u8) ![]u8 {
    const current_display = if (current_url) |url| url else "No current page";

    const html = try std.fmt.allocPrint(allocator,
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\  <head>
        \\    <meta charset="utf-8" />
        \\    <title>Navigation - Frontier Zig</title>
        \\    <style>
        \\      * {{ box-sizing: border-box; }}
        \\      html, body {{
        \\        margin: 0;
        \\        padding: 0;
        \\        width: 100%;
        \\        height: 100%;
        \\        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
        \\        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        \\        color: white;
        \\      }}
        \\      .container {{
        \\        display: flex;
        \\        flex-direction: column;
        \\        align-items: center;
        \\        justify-content: center;
        \\        min-height: 100vh;
        \\        padding: 40px 20px;
        \\      }}
        \\      .palette {{
        \\        background: rgba(255, 255, 255, 0.98);
        \\        border-radius: 16px;
        \\        box-shadow: 0 25px 50px rgba(0, 0, 0, 0.3);
        \\        width: 100%;
        \\        max-width: 700px;
        \\        overflow: hidden;
        \\      }}
        \\      .header {{
        \\        padding: 24px 24px 16px;
        \\        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        \\        color: white;
        \\      }}
        \\      .header h1 {{
        \\        margin: 0 0 8px 0;
        \\        font-size: 24px;
        \\        font-weight: 600;
        \\      }}
        \\      .header p {{
        \\        margin: 0;
        \\        opacity: 0.9;
        \\        font-size: 14px;
        \\      }}
        \\      .current {{
        \\        padding: 16px 24px;
        \\        background: #f8fafc;
        \\        border-bottom: 1px solid #e5e7eb;
        \\        font-size: 13px;
        \\        color: #64748b;
        \\      }}
        \\      .current strong {{
        \\        color: #0f172a;
        \\      }}
        \\      .instructions {{
        \\        padding: 24px;
        \\        color: #0f172a;
        \\      }}
        \\      .instructions h2 {{
        \\        margin: 0 0 16px 0;
        \\        font-size: 18px;
        \\        font-weight: 600;
        \\      }}
        \\      .instructions p {{
        \\        margin: 0 0 12px 0;
        \\        line-height: 1.6;
        \\        color: #475569;
        \\      }}
        \\      .command {{
        \\        background: #f1f5f9;
        \\        padding: 12px 16px;
        \\        border-radius: 8px;
        \\        font-family: 'SFMono-Regular', Consolas, monospace;
        \\        font-size: 14px;
        \\        margin: 16px 0;
        \\        color: #0f172a;
        \\        border: 1px solid #cbd5e1;
        \\      }}
        \\      .examples {{
        \\        margin-top: 20px;
        \\      }}
        \\      .example {{
        \\        background: #f8fafc;
        \\        padding: 10px 12px;
        \\        border-radius: 6px;
        \\        margin: 8px 0;
        \\        font-family: monospace;
        \\        font-size: 13px;
        \\        color: #475569;
        \\        border-left: 3px solid #667eea;
        \\      }}
        \\      .shortcut {{
        \\        display: inline-block;
        \\        padding: 2px 8px;
        \\        background: #e0e7ff;
        \\        border-radius: 4px;
        \\        font-size: 12px;
        \\        font-weight: 600;
        \\        color: #4338ca;
        \\        font-family: monospace;
        \\      }}
        \\    </style>
        \\  </head>
        \\  <body>
        \\    <div class="container">
        \\      <div class="palette">
        \\        <div class="header">
        \\          <h1>🚀 Frontier Zig Navigator</h1>
        \\          <p>Phase 2: Command-line navigation interface</p>
        \\        </div>
        \\        <div class="current">
        \\          Current: <strong>{s}</strong>
        \\        </div>
        \\        <div class="instructions">
        \\          <h2>How to Navigate</h2>
        \\          <p>To navigate to a URL, restart the application with a URL argument:</p>
        \\          <div class="command">
        \\            zig build run --build-file zig/build.zig -- &lt;URL&gt;
        \\          </div>
        \\          <p style="margin-top: 16px;">Or use the convenience wrapper:</p>
        \\          <div class="command">
        \\            just run -- &lt;URL&gt;
        \\          </div>
        \\
        \\          <div class="examples">
        \\            <p><strong>Examples:</strong></p>
        \\            <div class="example">file:///Users/justin/code/frontier-zig/worktrees/phase-two-plans-claude/assets/test.html</div>
        \\            <div class="example">file:///path/to/your/file.html</div>
        \\          </div>
        \\
        \\          <p style="margin-top: 24px;">
        \\            <strong>Try it!</strong> Press <span class="shortcut">Cmd+K</span> (or <span class="shortcut">Ctrl+K</span>) to toggle this command palette!
        \\          </p>
        \\          <p style="margin-top: 8px; font-size: 13px; color: #64748b;">
        \\            Note: Full interactive navigation with URL input will be available in Phase 3 with TypeScript support.
        \\          </p>
        \\        </div>
        \\      </div>
        \\    </div>
        \\  </body>
        \\</html>
    , .{current_display});

    return html;
}
