#!/bin/bash
set -e

OUTPUT="/tmp/frontier_zig_app.png"

echo "Building frontier-zig..."
zig build --build-file zig/build.zig

echo "Launching frontier-zig..."
zig/zig-out/bin/frontier-zig > /tmp/frontier_zig_output.log 2>&1 &
APP_PID=$!

echo "App PID: $APP_PID"
echo "Waiting for window to appear..."
sleep 3

# Get window info using AppleScript
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

if [ -n "$WINDOW_INFO" ]; then
    APP_NAME=$(echo "$WINDOW_INFO" | cut -d'|' -f1)
    WINDOW_TITLE=$(echo "$WINDOW_INFO" | cut -d'|' -f2)

    echo "Found app: $APP_NAME"
    [ -n "$WINDOW_TITLE" ] && echo "Window title: $WINDOW_TITLE"

    # Bring window to front for capture
    osascript 2>/dev/null <<EOF
tell application "System Events"
    set frontmost of application process "$APP_NAME" to true
end tell
EOF

    sleep 0.5
    screencapture -x -o "$OUTPUT"
    echo "Screenshot captured: $OUTPUT"
else
    echo "Using fallback screenshot method..."
    screencapture -x -o "$OUTPUT"
fi

# Kill app
kill $APP_PID 2>/dev/null || true
wait $APP_PID 2>/dev/null || true

if [ -f "$OUTPUT" ]; then
    SIZE=$(sips -g pixelWidth -g pixelHeight "$OUTPUT" 2>/dev/null | grep -E "pixel(Width|Height)" | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')
    FILESIZE=$(ls -lh "$OUTPUT" | awk '{print $5}')

    echo ""
    echo "✓ Screenshot: $OUTPUT"
    echo "  Dimensions: $SIZE"
    echo "  File size: $FILESIZE"
    echo ""

    open "$OUTPUT"
    echo "Screenshot available at: $OUTPUT"
else
    echo "✗ Screenshot failed"
    exit 1
fi
