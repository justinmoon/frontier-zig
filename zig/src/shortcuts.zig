const std = @import("std");
const command_palette = @import("command_palette.zig");
const navigation = @import("navigation.zig");

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

        // Generate modal HTML with text input
        const modal_div = command_palette.generateCommandPaletteModal(allocator, current_url) catch |err| {
            std.log.err("Failed to generate modal: {}", .{err});
            const fallback = "<div>Error generating command palette</div>";
            break :blk fallback;
        };

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

/// Extract the actual URL from a form submission URL with query parameters
/// e.g. "http://localhost/navigate?url=https%3A%2F%2Fexample.com" -> "https://example.com"
fn extractUrlFromQuery(url: []const u8) ![]const u8 {
    // Look for "?url=" in the URL
    const query_start = std.mem.indexOf(u8, url, "?url=") orelse return error.NoUrlParam;
    const encoded_url = url[query_start + 5..]; // Skip "?url="

    // URL decode the parameter
    var decoded = std.ArrayList(u8).empty;
    defer decoded.deinit(allocator);

    var i: usize = 0;
    while (i < encoded_url.len) {
        if (encoded_url[i] == '%' and i + 2 < encoded_url.len) {
            // Decode %XX hex sequence
            const hex = encoded_url[i+1..i+3];
            const byte = std.fmt.parseInt(u8, hex, 16) catch {
                try decoded.append(allocator, encoded_url[i]);
                i += 1;
                continue;
            };
            try decoded.append(allocator, byte);
            i += 3;
        } else if (encoded_url[i] == '+') {
            try decoded.append(allocator, ' ');
            i += 1;
        } else {
            try decoded.append(allocator, encoded_url[i]);
            i += 1;
        }
    }

    return try allocator.dupe(u8, decoded.items);
}

/// Navigate to a URL - called by Rust when user submits navigation
/// Returns HTML to display (either the fetched page or error page)
export fn frontier_navigate_to_url(url_ptr: [*]const u8, url_len: usize) HtmlResult {
    const url = url_ptr[0..url_len];
    std.log.info("Navigating to: {s}", .{url});

    // Hide command palette
    command_palette_visible = false;

    // Extract actual URL from query parameter if this is a form submission
    const actual_url = extractUrlFromQuery(url) catch url;
    const is_extracted = !std.mem.eql(u8, url, actual_url);
    defer if (is_extracted) allocator.free(actual_url);

    if (is_extracted) {
        std.log.info("Extracted URL from query: {s}", .{actual_url});
    }

    // Fetch the URL
    const html = navigation.fetchUrl(allocator, actual_url) catch |err| {
        std.log.err("Failed to fetch URL: {}", .{err});
        const error_html = std.fmt.allocPrint(allocator,
            \\<!DOCTYPE html>
            \\<html>
            \\<head><title>Error</title></head>
            \\<body style="font-family: sans-serif; padding: 40px; text-align: center;">
            \\  <h1 style="color: #e53e3e;">Navigation Error</h1>
            \\  <p style="color: #666; margin: 20px 0;">Failed to navigate to:</p>
            \\  <code style="background: #f5f5f5; padding: 8px 12px; border-radius: 4px; display: inline-block;">{s}</code>
            \\  <p style="color: #999; margin-top: 20px; font-size: 14px;">Press Cmd+K to try again</p>
            \\</body>
            \\</html>
        , .{actual_url}) catch {
            const fallback = "<html><body><h1>Error</h1></body></html>";
            return HtmlResult{ .ptr = fallback.ptr, .len = fallback.len };
        };
        // Store for cleanup
        if (last_generated_html) |old| {
            allocator.free(old);
        }
        last_generated_html = error_html;
        return HtmlResult{ .ptr = error_html.ptr, .len = error_html.len };
    };

    // Update current URL (use actual_url so we store the real destination)
    if (current_url) |old| {
        allocator.free(old);
    }
    current_url = allocator.dupe(u8, actual_url) catch null;

    // Save content so Cmd+K can restore it
    saveCurrentDocument(html) catch |err| {
        std.log.err("Failed to save document: {}", .{err});
    };

    // Store for cleanup
    if (last_generated_html) |old| {
        allocator.free(old);
    }
    last_generated_html = html;

    return HtmlResult{ .ptr = html.ptr, .len = html.len };
}
