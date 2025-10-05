# Command Palette Architecture

## Overview

The Frontier browser implements a Chrome-style command palette using a **modal overlay approach** activated by `Cmd+K`. This document describes the architecture and design decisions.

## Architecture

### High-Level Flow

```
User presses Cmd+K
    ↓
Rust detects keyboard shortcut
    ↓
Rust calls Zig FFI: frontier_get_command_palette_html()
    ↓
Zig generates HTML with modal overlay + form
    ↓
User types URL and presses Enter
    ↓
Form submits to /navigate?url=<encoded_url>
    ↓
Rust intercepts navigation, calls frontier_navigate_to_url()
    ↓
Zig extracts & decodes URL parameter
    ↓
Zig fetches HTTP/HTTPS content
    ↓
Returns HTML to Rust for rendering
```

### Key Components

#### 1. Keyboard Shortcut Detection (Rust)

**File:** `rust/src/lib.rs`

The Rust side detects `Cmd+K` in the keyboard event handler:

```rust
if modifiers.super_key() && event.logical_key == Key::Character("k") {
    // Call Zig to get command palette HTML
    let html_result = unsafe { frontier_get_command_palette_html() };
    // Load HTML into webview
}
```

#### 2. Modal Generation (Zig)

**Files:** `zig/src/shortcuts.zig`, `zig/src/command_palette.zig`

When `Cmd+K` is pressed, Zig generates HTML in two parts:

1. **Base page** - The navigation interface or saved content
2. **Modal overlay** - A semi-transparent overlay with text input

```zig
// Toggle state
command_palette_visible = !command_palette_visible;

if (command_palette_visible) {
    // Generate modal HTML with input field
    const modal_div = generateCommandPaletteModal(allocator, current_url);

    // Insert modal before </body> tag
    const result = std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        base_page[0..insertion_point],
        modal_div,
        base_page[insertion_point..],
    });
}
```

#### 3. Form Submission & URL Extraction

**File:** `zig/src/shortcuts.zig`

The modal contains a form that submits to `/navigate?url=<encoded>`:

```html
<form method="GET" action="/navigate" style="width: 100%; max-width: 600px;">
    <input type="text" name="url" placeholder="Enter URL..." />
</form>
```

When submitted, Rust intercepts the navigation and passes the full URL to Zig:

```zig
export fn frontier_navigate_to_url(url_ptr: [*]const u8, url_len: usize) HtmlResult {
    const url = url_ptr[0..url_len];

    // Extract actual URL from query parameter
    // "http://localhost/navigate?url=https%3A%2F%2Fexample.com"
    // -> "https://example.com"
    const actual_url = extractUrlFromQuery(url) catch url;

    // Fetch the URL
    const html = navigation.fetchUrl(allocator, actual_url);

    return HtmlResult{ .ptr = html.ptr, .len = html.len };
}
```

#### 4. URL Decoding

**File:** `zig/src/shortcuts.zig`

URL-encoded parameters are decoded using a custom decoder:

```zig
fn extractUrlFromQuery(url: []const u8) ![]const u8 {
    // Find "?url=" in the URL
    const query_start = std.mem.indexOf(u8, url, "?url=") orelse return error.NoUrlParam;
    const encoded_url = url[query_start + 5..];

    // Decode %XX hex sequences and + symbols
    var decoded = std.ArrayList(u8).empty;
    // ... decoding logic ...

    return try allocator.dupe(u8, decoded.items);
}
```

#### 5. HTTP Fetching

**File:** `zig/src/navigation.zig`

HTTP/HTTPS URLs are fetched using Zig 0.15.1's HTTP client with a temporary file pattern:

```zig
fn fetchHttp(allocator: std.mem.Allocator, parsed: ParsedUrl) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(parsed.original);

    // Use temporary file to capture response
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var tmp_file = try tmp_dir.dir.createFile("response.html", .{ .read = true });
    defer tmp_file.close();

    var writer = tmp_file.writer(&writer_buffer);

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .response_writer = &writer.interface,
    });

    // Read back from file
    try tmp_file.seekTo(0);
    return try tmp_file.readToEndAlloc(allocator, max_size);
}
```

## Design Decisions

### Why Modal Overlay?

**Alternatives considered:**
1. **Separate chrome window** - Complex to manage, harder to position
2. **Native OS dialog** - Not customizable, breaks web-first philosophy
3. **Browser devtools approach** - Too heavyweight for simple navigation

**Why modal overlay won:**
- Simple HTML/CSS implementation
- Easy to style and customize
- Integrates seamlessly with web rendering
- Can reuse existing page as background
- No window management complexity

### Why Form-Based Submission?

**Alternatives considered:**
1. **JavaScript event listeners** - Requires JS runtime
2. **Direct Zig input handling** - Complex text input state management
3. **Rust-side input capture** - Requires duplicating UI state

**Why form submission won:**
- Works without JavaScript
- Browser handles all input behavior (cursor, selection, clipboard)
- Natural URL encoding via form parameters
- Blitz already intercepts navigation events

### Why Zig 0.15.1 Temporary File Pattern?

**Problem:** Zig 0.15.1's HTTP client API changed significantly:
- Old: `client.open()` with `response_storage` buffer
- New: `client.fetch()` with `response_writer` interface

**Solution:** Write HTTP response to temporary file, then read back:
- Avoids complex streaming/buffering logic
- Temporary file automatically cleaned up
- Simple error handling
- Works reliably for responses of any size

## State Management

### Global State (Zig)

```zig
var command_palette_visible: bool = false;
var current_url: ?[]const u8 = null;
var saved_content_html: ?[]const u8 = null;
var last_generated_html: ?[]const u8 = null;
```

- **command_palette_visible** - Toggle for showing/hiding modal
- **current_url** - Tracks current page for display in input
- **saved_content_html** - Stores page content to restore after closing modal
- **last_generated_html** - Tracks allocated HTML for cleanup

### Memory Management

All HTML is allocated using Zig's allocator and returned to Rust via FFI:

```zig
pub const HtmlResult = extern struct {
    ptr: [*]const u8,
    len: usize,
};
```

Cleanup happens on next HTML generation:

```zig
if (last_generated_html) |old| {
    allocator.free(old);
    last_generated_html = null;
}
```

## User Experience

1. **Press Cmd+K** - Modal appears with text input focused
2. **Type URL** - Browser's native input handling (no JS required)
3. **Press Enter** - Form submits, URL is extracted and fetched
4. **Page loads** - Modal disappears, content displayed
5. **Press Cmd+K again** - Modal reappears over content

## Future Enhancements

- **History/Autocomplete** - Add recently visited URLs
- **Command support** - Handle special commands (e.g., `:reload`, `:back`)
- **Fuzzy search** - Search through bookmarks/history
- **Keyboard navigation** - Arrow keys for suggestions
- **Escape key** - Close modal without navigation

## Testing

Tested successfully with:
- ESPN.com (228KB HTML)
- Example.com (1.2KB HTML)
- File:// URLs (local files)

## Related Files

- `rust/src/lib.rs` - Keyboard handling, FFI calls
- `zig/src/shortcuts.zig` - Command palette logic, URL extraction
- `zig/src/command_palette.zig` - HTML generation
- `zig/src/navigation.zig` - URL fetching (HTTP/file)
