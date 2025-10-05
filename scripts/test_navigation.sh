#!/bin/bash
set -e

cd /Users/justin/code/frontier-zig/worktrees/phase-two-plans-claude

echo "Building and launching frontier-zig..."
just run > /tmp/nav_test.log 2>&1 &
APP_PID=$!

echo "App PID: $APP_PID"
sleep 3

# Get window
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
    echo "Failed to find window"
    kill $APP_PID 2>/dev/null || true
    exit 1
fi

APP_NAME=$(echo "$WINDOW_INFO" | cut -d'|' -f1)
echo "Found app: $APP_NAME"

# Bring to front
osascript 2>/dev/null <<EOF
tell application "System Events"
    set frontmost of application process "$APP_NAME" to true
end tell
EOF
sleep 0.5

# Take BEFORE screenshot
screencapture -x -o /tmp/nav_before.png
echo "✓ Before screenshot: /tmp/nav_before.png"

# Press Cmd+K to open palette
echo "Pressing Cmd+K..."
osascript 2>/dev/null <<EOF
tell application "System Events"
    tell process "$APP_NAME"
        keystroke "k" using {command down}
    end tell
end tell
EOF
sleep 1

# Take screenshot of palette
screencapture -x -o /tmp/nav_palette.png
echo "✓ Palette screenshot: /tmp/nav_palette.png"

# Click on the first link (file:///tmp/test.html)
# We'll simulate clicking at a position where the link should be
echo "Clicking navigation link..."
osascript 2>/dev/null <<EOF
tell application "System Events"
    tell process "$APP_NAME"
        click at {400, 400}
    end tell
end tell
EOF
sleep 2

# Take AFTER screenshot
screencapture -x -o /tmp/nav_after.png
echo "✓ After screenshot: /tmp/nav_after.png"

# Kill app
kill $APP_PID 2>/dev/null || true
wait $APP_PID 2>/dev/null || true

echo ""
echo "Opening screenshots..."
open /tmp/nav_before.png
open /tmp/nav_palette.png
open /tmp/nav_after.png

echo ""
echo "App logs:"
cat /tmp/nav_test.log
