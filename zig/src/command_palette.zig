const std = @import("std");

/// Generate the modal HTML snippet (NOT a full page)
/// This gets injected into shortcuts.zig
pub fn generateCommandPaletteModal(allocator: std.mem.Allocator, current_url: ?[]const u8) ![]u8 {
    const current_display = if (current_url) |url| url else "No current page";

    return std.fmt.allocPrint(allocator,
        \\  <style>
        \\    .cmd-palette-backdrop {{
        \\      position: fixed;
        \\      top: 0;
        \\      left: 0;
        \\      right: 0;
        \\      bottom: 0;
        \\      background: rgba(0, 0, 0, 0.6);
        \\      z-index: 9999;
        \\      display: flex;
        \\      align-items: flex-start;
        \\      justify-content: center;
        \\      padding-top: 15vh;
        \\    }}
        \\    .cmd-palette-modal {{
        \\      background: white;
        \\      border-radius: 12px;
        \\      box-shadow: 0 25px 50px rgba(0, 0, 0, 0.5);
        \\      width: 90%;
        \\      max-width: 600px;
        \\      overflow: hidden;
        \\    }}
        \\    .cmd-palette-header {{
        \\      padding: 20px 24px;
        \\      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        \\      color: white;
        \\    }}
        \\    .cmd-palette-header h1 {{
        \\      margin: 0 0 4px 0;
        \\      font-size: 20px;
        \\      font-weight: 600;
        \\    }}
        \\    .cmd-palette-header p {{
        \\      margin: 0;
        \\      opacity: 0.9;
        \\      font-size: 13px;
        \\    }}
        \\    .cmd-palette-form {{
        \\      padding: 20px 24px;
        \\      background: #f8fafc;
        \\    }}
        \\    .cmd-palette-input {{
        \\      width: 100%;
        \\      padding: 12px 16px;
        \\      font-size: 15px;
        \\      border: 2px solid #cbd5e1;
        \\      border-radius: 8px;
        \\      font-family: 'SFMono-Regular', Consolas, monospace;
        \\      color: #0f172a;
        \\      background: white;
        \\    }}
        \\    .cmd-palette-input:focus {{
        \\      outline: none;
        \\      border-color: #667eea;
        \\      box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.15);
        \\    }}
        \\    .cmd-palette-current {{
        \\      padding: 12px 24px;
        \\      background: white;
        \\      border-top: 1px solid #e5e7eb;
        \\      font-size: 12px;
        \\      color: #64748b;
        \\    }}
        \\    .cmd-palette-links {{
        \\      padding: 16px 24px 20px;
        \\      background: white;
        \\    }}
        \\    .cmd-palette-links h3 {{
        \\      margin: 0 0 10px 0;
        \\      font-size: 12px;
        \\      font-weight: 600;
        \\      color: #64748b;
        \\      text-transform: uppercase;
        \\      letter-spacing: 0.05em;
        \\    }}
        \\    .cmd-palette-link {{
        \\      display: block;
        \\      padding: 10px 14px;
        \\      margin: 6px 0;
        \\      background: #f8fafc;
        \\      border: 1px solid #e5e7eb;
        \\      border-radius: 6px;
        \\      text-decoration: none;
        \\      color: #0f172a;
        \\      font-family: monospace;
        \\      font-size: 12px;
        \\      transition: all 0.15s ease;
        \\    }}
        \\    .cmd-palette-link:hover {{
        \\      background: white;
        \\      border-color: #667eea;
        \\      transform: translateX(4px);
        \\    }}
        \\    .cmd-palette-hint {{
        \\      padding: 12px 24px;
        \\      text-align: center;
        \\      font-size: 11px;
        \\      color: #94a3b8;
        \\      background: #f8fafc;
        \\      border-top: 1px solid #e5e7eb;
        \\    }}
        \\  </style>
        \\  <div class="cmd-palette-backdrop">
        \\    <div class="cmd-palette-modal">
        \\      <div class="cmd-palette-header">
        \\        <h1>🌐 Navigate</h1>
        \\        <p>Type a URL or click a link below</p>
        \\      </div>
        \\      <div class="cmd-palette-form">
        \\        <form action="/navigate" method="get">
        \\          <input
        \\            type="text"
        \\            name="url"
        \\            class="cmd-palette-input"
        \\            placeholder="Enter URL (e.g., https://example.com or file:///tmp/test.html)"
        \\            autofocus
        \\          />
        \\          <input type="submit" value="Navigate" style="display: none;" />
        \\        </form>
        \\      </div>
        \\      <div class="cmd-palette-current">
        \\        Current: <strong>{s}</strong>
        \\      </div>
        \\      <div class="cmd-palette-links">
        \\        <h3>Quick Links</h3>
        \\        <a href="file:///tmp/page1.html" class="cmd-palette-link">→ file:///tmp/page1.html</a>
        \\        <a href="file:///tmp/page2.html" class="cmd-palette-link">→ file:///tmp/page2.html</a>
        \\        <a href="file:///tmp/test.html" class="cmd-palette-link">→ file:///tmp/test.html</a>
        \\      </div>
        \\      <div class="cmd-palette-hint">
        \\        Press Cmd+K to close • Enter to navigate
        \\      </div>
        \\    </div>
        \\  </div>
    , .{current_display});
}

/// Generate a full page (used for initial load when no URL provided)
pub fn generateCommandPaletteHtml(allocator: std.mem.Allocator, current_url: ?[]const u8) ![]u8 {
    const current_display = if (current_url) |url| url else "No current page";

    const html = try std.fmt.allocPrint(allocator,
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\  <head>
        \\    <meta charset="utf-8" />
        \\    <title>Navigate - Frontier Zig</title>
        \\  </head>
        \\  <body style="margin: 0; font-family: -apple-system, sans-serif; background: #f5f5f5;">
        \\    <div style="padding: 40px; text-align: center;">
        \\      <h1 style="color: #667eea;">Frontier Zig</h1>
        \\      <p style="color: #666;">Current: {s}</p>
        \\      <p style="color: #999; font-size: 14px; margin-top: 20px;">Press Cmd+K to navigate</p>
        \\    </div>
        \\  </body>
        \\</html>
    , .{current_display});

    return html;
}
