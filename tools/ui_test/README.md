# CCLUA Desktop UI Test Harness

This harness executes the real CCLUA Desktop Lua code outside Minecraft.

It emulates the 51x19 Advanced Computer terminal, CC:Tweaked colors, keys,
filesystem reads, timers, and coroutine event delivery. The compositor and
desktop applications are loaded directly from src/usr/lib/cclua/desktop.

Run:

    python tools/ui_test/desktop_ui_test.py

Outputs are written to:

    artifacts/desktop-ui/

The contact sheet contains every tested state in one image.

Current scripted coverage:

- empty workspace
- Terminal launch and typed command
- Files
- Settings
- Ubuntu Software search
- maximize/restore path
- overlapping windows and Alt+Tab
- dragging
- resizing
- closing

Each scenario asserts that the Lua coroutine remains alive and that the
framebuffer is exactly 51 columns by 19 rows.

Host dependencies:

    pip install lupa pillow
