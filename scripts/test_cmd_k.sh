#!/bin/bash
set -e

OUTPUT_BEFORE="/tmp/frontier_zig_before_cmdk.png"
OUTPUT_AFTER="/tmp/frontier_zig_after_cmdk.png"

echo "Building frontier-zig..."
zig build --build-file zig/build.zig

echo "Launching frontier-zig..."
RUST_LOG=info zig/zig-out/bin/frontier-zig > /tmp/frontier_zig_output.log 2>&1 &
APP_PID=$!

echo "App PID: $APP_PID"
echo "Waiting for window to appear..."
sleep 3

# Get app name
WINDOW_INFO=$(osascript 2>/dev/null <<EOF || echo ""
tell application "System Events"
    set appName to name of first application process whose unix id is $APP_PID
    try
        set windowTitle to name of window 1 of application process appName
        return appName & "|" & windowTitle
    on error
        return appName & "|"
    end try
end tell
EOF
)

if [ -z "$WINDOW_INFO" ]; then
    echo "Failed to find app window"
    kill $APP_PID 2>/dev/null || true
    exit 1
fi

APP_NAME=$(echo "$WINDOW_INFO" | cut -d'|' -f1)
WINDOW_TITLE=$(echo "$WINDOW_INFO" | cut -d'|' -f2)

echo "Found app: $APP_NAME"
[ -n "$WINDOW_TITLE" ] && echo "Window title: $WINDOW_TITLE"

# Bring window to front and click it to ensure focus
osascript 2>/dev/null <<EOF
tell application "System Events"
    set frontmost of application process "$APP_NAME" to true
    delay 0.3
    -- Click center of window to give it focus
    tell process "$APP_NAME"
        click window 1
    end tell
end tell
EOF

sleep 0.5

# Take BEFORE screenshot
echo "Taking BEFORE screenshot..."
screencapture -x -o "$OUTPUT_BEFORE"

echo "Sending Cmd+K..."
# Send Cmd+K keyboard event
osascript 2>/dev/null <<EOF
tell application "System Events"
    tell process "$APP_NAME"
        keystroke "k" using {command down}
    end tell
end tell
EOF

# Wait for UI to update
echo "Waiting for UI update..."
sleep 1

# Take AFTER screenshot
echo "Taking AFTER screenshot..."
screencapture -x -o "$OUTPUT_AFTER"

# Kill app
echo "Killing app..."
kill $APP_PID 2>/dev/null || true
wait $APP_PID 2>/dev/null || true

# Check results
echo ""
echo "=== RESULTS ==="
echo ""

if [ -f "$OUTPUT_BEFORE" ]; then
    SIZE=$(sips -g pixelWidth -g pixelHeight "$OUTPUT_BEFORE" 2>/dev/null | grep -E "pixel(Width|Height)" | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')
    echo "✓ BEFORE screenshot: $OUTPUT_BEFORE ($SIZE)"
else
    echo "✗ BEFORE screenshot failed"
fi

if [ -f "$OUTPUT_AFTER" ]; then
    SIZE=$(sips -g pixelWidth -g pixelHeight "$OUTPUT_AFTER" 2>/dev/null | grep -E "pixel(Width|Height)" | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')
    echo "✓ AFTER screenshot: $OUTPUT_AFTER ($SIZE)"
else
    echo "✗ AFTER screenshot failed"
fi

echo ""
echo "Check logs:"
echo "  cat /tmp/frontier_zig_output.log"
echo ""
echo "Opening screenshots..."
open "$OUTPUT_BEFORE"
open "$OUTPUT_AFTER"
