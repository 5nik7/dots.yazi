---
name: dots-yazi-ui
description: Maintain dots.yazi components, theme callbacks and file styling without redraw-time I/O. Use for Dotline, hover or live palette integration.
---

# Dots Yazi Ui

Read [architecture](../../../docs/architecture.md), [configuration](../../../README.md) and [agent rules](../../../AGENTS.md).

Trace a setting from main setup through the component getter to the actual redraw. Dotline getters may be called as plain functions; do not assume a self argument. Keep ya.sync declarations at module scope and palette changes separate from feature setup. A theme event must not duplicate subscriptions, restart Git work or reset projects/panes.

Keep full styles intact: foreground, background, resets and false attributes all matter. Preserve explicit hover-part overrides and symlink/target distinctions. Use cached MIME metadata; never probe files or invoke tools during redraw. Reject malformed snapshots before swapping last-good state.

Run component Lua cases plus test-theme-native.py for actual dark/light and mode rendering. When updating Dots too, compare both worktrees and sync reviewed runtime files; keep separate Git histories and validate the copied personal config in an owned fixture.
