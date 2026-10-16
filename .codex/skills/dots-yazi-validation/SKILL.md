---
name: dots-yazi-validation
description: Validate dots.yazi using Lua fixtures, GNU ls comparisons and private native Yazi sessions. Use for plugin regression checks and rendering evidence.
---

# Dots Yazi Validation

Read [test entry points](../../../docs/testing.md) before running checks.

Run Lua tests before native PTYs. test-ls-colors.py compares the resolver with GNU ls; test-native.py covers Git/projects/panes/hover using included configs or an explicit --config-dir. test-theme-native.py covers live publication and last-good recovery. Native tests must own HOME, XDG roots, Yazi configuration, TMPDIR and DDS sockets; never publish test events to a live session.

Use real UI context for cx and Dotline probes (a sync entry or module-scope ya.sync). Review native mode transitions and complete redraws, not just helper return values. Keep process cleanup bounded and sequential on Termux. Distinguish optional-tool skips from successful platform evidence.

Validate Markdown links, Lua syntax and git diff --check. If coordinating with Dots, run its tools/check_yazi_bundle.py against this checkout after syncing shared sources. Do not copy .git or machine state into fixtures.
