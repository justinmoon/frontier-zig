#!/bin/bash
set -e

cd /Users/justin/code/frontier-zig/worktrees/phase-two-plans-claude/rust

echo "Building modal demo..."
cargo build --example modal_demo --quiet

echo "Launching demo..."
cargo run --example modal_demo > /tmp/modal_demo_run.log 2>&1 &
DEMO_PID=$!

echo "Demo PID: $DEMO_PID"
sleep 3

# Get window
WINDOW_INFO=$(osascript 2>/dev/null <<EOF || echo ""
tell application "System Events"
    set appName to name of first application process whose unix id is $DEMO_PID
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
    kill $DEMO_PID 2>/dev/null || true
    exit 1
fi

APP_NAME=$(echo "$WINDOW_INFO" | cut -d'|' -f1)
echo "Found app: $APP_NAME"

# Take BEFORE screenshot
osascript 2>/dev/null <<EOF
tell application "System Events"
    set frontmost of application process "$APP_NAME" to true
end tell
EOF
sleep 0.5
screencapture -x -o /tmp/modal_before.png
echo "✓ Before screenshot: /tmp/modal_before.png"

# Press Cmd+K
echo "Pressing Cmd+K..."
osascript 2>/dev/null <<EOF
tell application "System Events"
    tell process "$APP_NAME"
        keystroke "k" using {command down}
    end tell
end tell
EOF

sleep 1

# Take AFTER screenshot
screencapture -x -o /tmp/modal_after.png
echo "✓ After screenshot: /tmp/modal_after.png"

# Kill demo
kill $DEMO_PID 2>/dev/null || true
wait $DEMO_PID 2>/dev/null || true

echo ""
echo "Opening screenshots..."
open /tmp/modal_before.png
open /tmp/modal_after.png

echo ""
echo "Demo logs:"
cat /tmp/modal_demo_run.log
