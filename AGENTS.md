# dots.yazi agent guide

This repository owns the standalone Dots Yazi plugin. Read README.md and the
relevant docs before changing behavior. Preserve dirty work and upstream notices.
The main Dots checkout separately tracks a bundled runtime copy; do not replace
that directory or convert repository boundaries as part of a feature change.

- Runtime entry/setup is main.lua; Dotline owns layout; theme.lua owns published
  palette loading; ls-colors.lua owns file-style matching and installed pane hooks.
- Keep I/O and subprocesses out of redraw functions. Declare ya.sync boundaries
  at module scope; do not install duplicate subscriptions or hooks on color refresh.
- Existing options and explicit false values remain compatible. Keep foreground,
  background and attributes together when passing complete file styles.
- Tests own HOME, XDG roots, Yazi config, DDS runtime and all filesystem fixtures.
  Never use live project state, Git credentials or the user's running Yazi server.
- Follow docs/testing.md for Lua, GNU ls and native PTY checks. Run sequentially
  on Termux; report missing native tools as unverified rather than silently passing.
- Update README/config examples, docs and tests with every public behavior change.
  Keep the standalone runners usable without a parent Dots checkout.
- No commits, pushes, package installs or unrelated removals without authorization.

Local skills are indexed in .codex/README.md. They supplement this guide rather
than duplicating project rules.

Keep `.agents/skills` discovery directories real; use file symlinks to canonical
`.codex/skills` content. Yazi package materialization rejects directory symlinks.
Run `python3 -B test-package.py` for packaging or discovery-layout changes.
