const std = @import("std");
const command_palette = @import("command_palette.zig");

// Keyboard shortcut IDs (must match Rust side)
pub const SHORTCUT_CMD_K: u8 = 1;
pub const SHORTCUT_CMD_R: u8 = 2;

// Global state
var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa_instance.allocator();

var command_palette_visible: bool = false;
var current_url: ?[]const u8 = null;
var saved_content_html: ?[]const u8 = null;
var last_generated_html: ?[]const u8 = null; // Track allocated HTML for cleanup

// Struct to return HTML to Rust (Rust will manage memory)
pub const HtmlResult = extern struct {
    ptr: [*]const u8,
    len: usize,
};

/// Called by Rust when Cmd+K is pressed
/// Returns the HTML to display (command palette or restore previous)
/// Rust is responsible for freeing the memory by calling frontier_free_html()
export fn frontier_get_command_palette_html() HtmlResult {
    toggleCommandPalette() catch |err| {
        std.log.err("Failed to toggle command palette: {}", .{err});
        // Return error HTML
        const error_html = "<html><body><h1>Error toggling command palette</h1></body></html>";
        return HtmlResult{
            .ptr = error_html.ptr,
            .len = error_html.len,
        };
    };

    std.log.info("Returning HTML, palette visible: {}", .{command_palette_visible});

    // Free previously generated HTML
    if (last_generated_html) |old| {
        allocator.free(old);
        last_generated_html = null;
    }

    const html = if (command_palette_visible) blk: {
        // Generate base page (the navigation interface)
        const base_page = if (saved_content_html) |saved| saved else blk2: {
            // Generate nav interface as base
            const nav_html = command_palette.generateCommandPaletteHtml(allocator, current_url) catch |err| {
                std.log.err("Failed to generate nav: {}", .{err});
                const fallback = "<html><body><h1>Navigation Interface</h1></body></html>";
                break :blk2 fallback;
            };
            break :blk2 nav_html;
        };

        std.log.info("Base page length: {} bytes", .{base_page.len});

        // Find </body> tag and insert modal before it
        const modal_div =
            \\  <style>
            \\    .cmd-palette-backdrop {
            \\      position: fixed;
            \\      top: 0;
            \\      left: 0;
            \\      right: 0;
            \\      bottom: 0;
            \\      background: rgba(0, 0, 0, 0.5);
            \\      z-index: 9999;
            \\      display: flex;
            \\      align-items: flex-start;
            \\      justify-content: center;
            \\      padding-top: 20vh;
            \\    }
            \\    .cmd-palette-modal {
            \\      background: white;
            \\      border-radius: 8px;
            \\      box-shadow: 0 25px 50px rgba(0, 0, 0, 0.5);
            \\      width: 90%;
            \\      max-width: 600px;
            \\      padding: 24px;
            \\    }
            \\    .cmd-palette-modal h1 {
            \\      margin: 0 0 16px 0;
            \\      font-size: 24px;
            \\      color: #333;
            \\    }
            \\    .cmd-palette-modal input {
            \\      width: 100%;
            \\      padding: 12px;
            \\      font-size: 16px;
            \\      border: 2px solid #ddd;
            \\      border-radius: 4px;
            \\    }
            \\    .cmd-palette-modal p {
            \\      margin: 16px 0 0 0;
            \\      color: #666;
            \\      font-size: 14px;
            \\    }
            \\  </style>
            \\  <div class="cmd-palette-backdrop">
            \\    <div class="cmd-palette-modal">
            \\      <h1>🚀 Command Palette</h1>
            \\      <input type="text" placeholder="Enter URL to navigate..." autofocus />
            \\      <p>Press Cmd+K to close | Phase 2: Command-line navigation</p>
            \\    </div>
            \\  </div>
        ;

        // Insert modal before </body>
        const body_close_tag = "</body>";
        const insertion_point = std.mem.lastIndexOf(u8, base_page, body_close_tag);

        const modal_html = if (insertion_point) |pos| blk2: {
            // Insert modal div before </body>
            const result = std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
                base_page[0..pos],
                modal_div,
                base_page[pos..],
            }) catch |err| {
                std.log.err("Failed to insert modal: {}", .{err});
                break :blk2 base_page;
            };
            break :blk2 result;
        } else blk2: {
            // No </body> tag, just append modal
            const result = std.fmt.allocPrint(allocator, "{s}{s}", .{base_page, modal_div}) catch |err| {
                std.log.err("Failed to append modal: {}", .{err});
                break :blk2 base_page;
            };
            break :blk2 result;
        };

        break :blk modal_html;
    } else blk: {
        // Just show the base page without modal
        if (saved_content_html) |saved| {
            break :blk allocator.dupe(u8, saved) catch saved;
        } else {
            // No saved content - show navigation interface
            break :blk command_palette.generateCommandPaletteHtml(allocator, current_url) catch |err| {
                std.log.err("Failed to generate nav HTML: {}", .{err});
                const error_html = "<html><body><h1>Error</h1></body></html>";
                break :blk error_html;
            };
        }
    };

    // Store for cleanup next time
    last_generated_html = html;

    return HtmlResult{
        .ptr = html.ptr,
        .len = html.len,
    };
}

/// Free HTML returned by frontier_get_command_palette_html
export fn frontier_free_html(ptr: [*]const u8, len: usize) void {
    // For now, we're returning static strings, so nothing to free
    // In future, we'd: allocator.free(ptr[0..len]);
    _ = ptr;
    _ = len;
}

fn toggleCommandPalette() !void {
    // Just toggle state - Rust will call frontier_get_command_palette_html() to get the result
    command_palette_visible = !command_palette_visible;
    std.log.info("Command palette toggled, now visible: {}", .{command_palette_visible});
}

fn reloadCurrentPage() void {
    std.log.info("Reload requested (not yet implemented)", .{});
    // TODO: Implement reload in Phase 3
}

/// Initialize shortcuts module - call this from main
pub fn init(initial_url: ?[]const u8) void {
    current_url = initial_url;
}

/// Save the current document HTML before showing command palette
pub fn saveCurrentDocument(html: []const u8) !void {
    if (saved_content_html) |old| {
        allocator.free(old);
    }
    saved_content_html = try allocator.dupe(u8, html);
}
