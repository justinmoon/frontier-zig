const std = @import("std");

pub const UrlScheme = enum {
    http,
    https,
    file,

    pub fn fromString(scheme: []const u8) ?UrlScheme {
        if (std.mem.eql(u8, scheme, "http")) return .http;
        if (std.mem.eql(u8, scheme, "https")) return .https;
        if (std.mem.eql(u8, scheme, "file")) return .file;
        return null;
    }
};

pub const ParsedUrl = struct {
    scheme: UrlScheme,
    host: []const u8,
    port: ?u16,
    path: []const u8,
    original: []const u8,

    pub fn parse(allocator: std.mem.Allocator, url: []const u8) !ParsedUrl {
        const scheme_sep = std.mem.indexOf(u8, url, "://") orelse {
            return error.InvalidUrl;
        };

        const scheme_str = url[0..scheme_sep];
        const scheme = UrlScheme.fromString(scheme_str) orelse {
            return error.UnsupportedScheme;
        };

        if (scheme == .file) {
            const path = url[scheme_sep + 3 ..];
            return ParsedUrl{
                .scheme = scheme,
                .host = "",
                .port = null,
                .path = path,
                .original = url,
            };
        }

        const after_scheme = url[scheme_sep + 3 ..];
        const path_sep = std.mem.indexOfScalar(u8, after_scheme, '/');
        const host_port = if (path_sep) |idx| after_scheme[0..idx] else after_scheme;
        const path = if (path_sep) |idx| after_scheme[idx..] else "/";

        var host: []const u8 = host_port;
        var port: ?u16 = null;

        if (std.mem.lastIndexOfScalar(u8, host_port, ':')) |colon_idx| {
            host = host_port[0..colon_idx];
            const port_str = host_port[colon_idx + 1 ..];
            port = std.fmt.parseInt(u16, port_str, 10) catch null;
        }

        _ = allocator;
        return ParsedUrl{
            .scheme = scheme,
            .host = host,
            .port = port,
            .path = path,
            .original = url,
        };
    }
};

pub const NavigationEntry = struct {
    url: []const u8,
    title: ?[]const u8,
    timestamp: i64,
};

pub const NavigationHistory = struct {
    entries: std.ArrayList(NavigationEntry),
    current_index: ?usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) NavigationHistory {
        return .{
            .entries = std.ArrayList(NavigationEntry).init(allocator),
            .current_index = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *NavigationHistory) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.url);
            if (entry.title) |title| {
                self.allocator.free(title);
            }
        }
        self.entries.deinit();
    }

    pub fn navigate(self: *NavigationHistory, url: []const u8) !void {
        const url_copy = try self.allocator.dupe(u8, url);
        const timestamp = std.time.milliTimestamp();

        const entry = NavigationEntry{
            .url = url_copy,
            .title = null,
            .timestamp = timestamp,
        };

        // Clear forward history if we're not at the end
        if (self.current_index) |idx| {
            if (idx < self.entries.items.len - 1) {
                var i = idx + 1;
                while (i < self.entries.items.len) : (i += 1) {
                    const old_entry = self.entries.items[i];
                    self.allocator.free(old_entry.url);
                    if (old_entry.title) |title| {
                        self.allocator.free(title);
                    }
                }
                self.entries.shrinkRetainingCapacity(idx + 1);
            }
        }

        try self.entries.append(entry);
        self.current_index = self.entries.items.len - 1;
    }

    pub fn canGoBack(self: *NavigationHistory) bool {
        if (self.current_index) |idx| {
            return idx > 0;
        }
        return false;
    }

    pub fn canGoForward(self: *NavigationHistory) bool {
        if (self.current_index) |idx| {
            return idx < self.entries.items.len - 1;
        }
        return false;
    }

    pub fn goBack(self: *NavigationHistory) ?[]const u8 {
        if (self.canGoBack()) {
            self.current_index = self.current_index.? - 1;
            return self.entries.items[self.current_index.?].url;
        }
        return null;
    }

    pub fn goForward(self: *NavigationHistory) ?[]const u8 {
        if (self.canGoForward()) {
            self.current_index = self.current_index.? + 1;
            return self.entries.items[self.current_index.?].url;
        }
        return null;
    }

    pub fn currentUrl(self: *NavigationHistory) ?[]const u8 {
        if (self.current_index) |idx| {
            return self.entries.items[idx].url;
        }
        return null;
    }
};

pub fn fetchUrl(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    const parsed = try ParsedUrl.parse(allocator, url);

    switch (parsed.scheme) {
        .file => {
            return fetchFile(allocator, parsed.path);
        },
        .http, .https => {
            return fetchHttp(allocator, parsed);
        },
    }
}

fn fetchFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const max_size = 10 * 1024 * 1024; // 10MB
    return try file.readToEndAlloc(allocator, max_size);
}

fn fetchHttp(allocator: std.mem.Allocator, parsed: ParsedUrl) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(parsed.original);

    // Create a temporary file to write the response to
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var tmp_file = try tmp_dir.dir.createFile("response.html", .{ .read = true });
    defer tmp_file.close();

    var writer_buffer: [8 * 1024]u8 = undefined;
    var redirect_buffer: [8 * 1024]u8 = undefined;

    var writer = tmp_file.writer(&writer_buffer);

    const result = try client.fetch(.{
        .location = .{ .uri = uri },
        .method = .GET,
        .redirect_buffer = &redirect_buffer,
        .response_writer = &writer.interface,
    });

    _ = result; // status available if needed

    // Flush the writer
    try writer.interface.flush();

    // Read back from the file
    try tmp_file.seekTo(0);
    const max_size = 10 * 1024 * 1024; // 10MB
    const body = try tmp_file.readToEndAlloc(allocator, max_size);

    return body;
}

test "parse http url" {
    const url = "https://example.com:8080/path/to/page";
    const parsed = try ParsedUrl.parse(std.testing.allocator, url);

    try std.testing.expectEqual(UrlScheme.https, parsed.scheme);
    try std.testing.expectEqualStrings("example.com", parsed.host);
    try std.testing.expectEqual(@as(?u16, 8080), parsed.port);
    try std.testing.expectEqualStrings("/path/to/page", parsed.path);
}

test "parse file url" {
    const url = "file:///Users/test/file.html";
    const parsed = try ParsedUrl.parse(std.testing.allocator, url);

    try std.testing.expectEqual(UrlScheme.file, parsed.scheme);
    try std.testing.expectEqualStrings("/Users/test/file.html", parsed.path);
}

test "navigation history" {
    var history = NavigationHistory.init(std.testing.allocator);
    defer history.deinit();

    try history.navigate("https://example.com");
    try std.testing.expectEqualStrings("https://example.com", history.currentUrl().?);
    try std.testing.expect(!history.canGoBack());
    try std.testing.expect(!history.canGoForward());

    try history.navigate("https://example.com/page2");
    try std.testing.expect(history.canGoBack());
    try std.testing.expect(!history.canGoForward());

    const back_url = history.goBack();
    try std.testing.expectEqualStrings("https://example.com", back_url.?);
    try std.testing.expect(history.canGoForward());

    const forward_url = history.goForward();
    try std.testing.expectEqualStrings("https://example.com/page2", forward_url.?);
}
