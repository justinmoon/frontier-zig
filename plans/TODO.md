# Phase 2 Completion Tasks

## Current Status
✅ Keyboard shortcuts (Cmd+K) working
✅ Modal overlay with transparent backdrop working
✅ Navigation architecture implemented via `NavigationProvider`
✅ Zig+Rust FFI boundary proven viable

## What's Left to Complete Phase 2

### 1. Make navigation actually work in the UI
**Status:** Code is written but needs testing/debugging

**The issue:** Navigation is hooked up but may need event loop tweaking.

**What to do:**
1. Test clicking links in the command palette
2. Check logs for "Navigation requested to: ..." and "Got HTML from Zig navigation"
3. If navigation doesn't apply immediately, the pending navigation check in `new_events()` might need to trigger a redraw
4. Consider using `window().request_redraw()` after storing pending navigation

**Files to check:**
- `rust/src/lib.rs:165-178` - The `new_events()` handler that applies pending navigation
- `rust/src/lib.rs:71-98` - The NavigationProvider implementation

### 2. Fix white text issue (if still present)
**Status:** Should be fixed by the modal CSS updates

The modal now has explicit `color: #333` for all text. If white text appears:
- Check that the gradient background from `command_palette.zig` isn't overriding it
- The modal CSS has higher specificity so should work

### 3. Add proper URL input (Phase 3 feature, optional for Phase 2)
**Current:** Shows hardcoded links (file:///tmp/test.html, https://example.com)
**Phase 3:** Add text input that navigates on Enter

This is technically a Phase 3 feature per the original plan, but you mentioned wanting it for Phase 2.

**To implement:**
- Can't use pure HTML forms (Blitz doesn't handle them well)
- Options:
  a. Keep current click-based navigation for Phase 2
  b. Use JavaScript `window.location` hack (may not work in Blitz)
  c. Add keyboard event handler to detect Enter key and extract input value

**Recommended:** Keep click-based for Phase 2, add input field in Phase 3

### 4. Error handling improvements
**Current:** Basic error pages exist
**Todo:**
- Test `frontier_navigate_to_url()` with invalid URLs
- Test with URLs that fail to fetch (network errors)
- Verify error HTML displays correctly

### 5. Test with real URLs
**Test file:/// URLs:**
```bash
echo "<h1>Test Page</h1>" > /tmp/test.html
just run
# Press Cmd+K, click file:///tmp/test.html
```

**Test https:// URLs:**
Note: `navigation.zig` currently has a placeholder for HTTP. Need to implement actual HTTP fetching.

**To add HTTP support:**
1. Add HTTP client to `zig/build.zig` dependencies (e.g., `zap` or `http`)
2. Implement in `zig/src/navigation.zig:24` where it says "// TODO: HTTP(S) fetch"
3. Or just return an error page for now and add in Phase 3

### 6. Memory management audit
**Current concern:** `last_generated_html` in shortcuts.zig gets freed/reallocated

**Todo:**
- Verify no memory leaks when navigating multiple times
- Test: Click link → Cmd+K → Click different link → Repeat 10x
- Check if freed pointers are accessed (run with sanitizers if needed)

### 7. Polish for demo
**Before showing this off:**
- [ ] Verify Cmd+K toggles palette on/off
- [ ] Verify clicking link navigates successfully
- [ ] Verify Cmd+K shows palette over the new page
- [ ] Create a nice test.html with links to demonstrate multi-page navigation

## Quick Test Procedure

```bash
# 1. Create test content
cat > /tmp/page1.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Page 1</title></head>
<body style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; font-family: sans-serif;">
    <h1>Page 1</h1>
    <p>Press Cmd+K to navigate</p>
    <a href="file:///tmp/page2.html">Go to Page 2</a>
</body>
</html>
EOF

cat > /tmp/page2.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Page 2</title></head>
<body style="background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); color: white; padding: 40px; font-family: sans-serif;">
    <h1>Page 2</h1>
    <p>Press Cmd+K to navigate</p>
    <a href="file:///tmp/page1.html">Go to Page 1</a>
</body>
</html>
EOF

# 2. Run app
just run -- file:///tmp/page1.html

# 3. Test:
# - Press Cmd+K → See palette
# - Click file:///tmp/test.html → Should navigate
# - Press Cmd+K → See palette over new page
# - Click other link → Navigate again
```

## If Navigation Doesn't Work

**Check these in order:**

1. **Are navigation events firing?**
   ```bash
   just run 2>&1 | grep -i "navigation"
   ```
   Should see: "Navigation requested to: ..."

2. **Is Zig being called?**
   Look for: "Navigating to: ..." (from Zig)

3. **Is HTML being returned?**
   Look for: "Got HTML from Zig navigation (NNN bytes)"

4. **Is pending navigation being stored?**
   Add debug print in `new_events()` to check

5. **Is update_document being called?**
   Look for: "Applying pending navigation to: ..."

**Common issue:** The pending navigation check happens in `new_events()` but might not trigger until the next frame. Solution: Call `window().request_redraw()` after storing pending navigation.

## Architecture Notes for Future Devs

### Why this approach works:

**Blitz provides NavigationProvider specifically for embedders.** This is the official way to handle link clicks and form submissions. Dioxus doesn't need it because it's a virtual DOM framework with direct Rust event handlers.

### The flow:

```
User clicks <a href="...">
    ↓
Blitz detects click on link
    ↓
Blitz calls NavigationProvider::navigate_to(url)
    ↓
Rust calls frontier_navigate_to_url() via FFI
    ↓
Zig fetches URL, returns HTML
    ↓
Rust stores (html, url) in pending_navigation
    ↓
Next frame: new_events() checks pending_navigation
    ↓
If Some: calls update_document(html, url)
    ↓
Document updated, user sees new page
```

### Why the "pending navigation" pattern:

NavigationProvider::navigate_to() doesn't have mutable access to the document. We can't update it directly. So we:
1. Store the navigation in shared state
2. Apply it in the next event loop iteration where we DO have mutable access

This is a standard pattern for async updates in event loops.

### FFI Safety:

**Current approach:**
- Zig returns HtmlResult with ptr/len
- Rust reads it immediately, copies to owned String
- Zig stores the allocation in `last_generated_html`
- Next call: Zig frees old, stores new

**Memory lifecycle:**
1. Zig allocates HTML string
2. Zig stores pointer in `last_generated_html` for cleanup
3. Zig returns raw pointer to Rust
4. Rust copies to owned String
5. Next navigation: Zig frees old `last_generated_html`, allocates new

**Potential issue:** If Rust holds the pointer past the next navigation call, it's UB. Current code is safe because we `.to_owned()` immediately.

## Phase 3 Preview

Once Phase 2 is solid, Phase 3 adds:

1. **Text input in command palette**
   - Type URL, press Enter to navigate
   - Requires either JS interop or keyboard event polling

2. **HTTP/HTTPS support**
   - Add HTTP client to Zig
   - Implement in navigation.zig

3. **History/Back button**
   - Store navigation history in Zig
   - Cmd+[ for back, Cmd+] for forward

4. **Bookmarks**
   - Store in SQLite or JSON
   - Show in command palette

5. **Tab support**
   - Multiple documents in BlitzApplication
   - Cmd+T for new tab, Cmd+W to close
