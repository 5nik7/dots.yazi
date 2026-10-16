# Architecture

`main.lua` installs bundled features once and routes actions without changing their
arguments. Dotline renders headers/status; hover supplies fitted path/link spans;
githead keeps asynchronous Git results separate from command-free rendering.

`theme.lua` loads schema-1 Dots colors.json from a complete published generation.
It validates identity, mode, color/style groups and LS_COLORS before swapping the
snapshot. The state marker identifies the generation. Duplicate notifications do
no work; malformed snapshots retain previous state and expose `last_error`.
DDS messages only trigger a read from the configured state root. They cannot
supply arbitrary files or code. Yazi's local theme event and manual theme-refresh
use the same path. No timer or redraw-time file read is installed.

Theme callbacks map named colors and apply UI style overlays. Githead recoloring
updates its existing closures without restarting refresh work. Hover's existing
idempotent hooks are retained. Structural layouts remain owned by normal setup.
The LS_COLORS resolver preserves core precedence, suffix collision behavior,
backgrounds and attributes; Dots adds explicit MIME overrides using cached metadata.

This repository owns shared runtime source. Dots tracks a bundled copy under its
Yazi config; synchronize selected shared files after reviewing both worktrees.
Keep tests/docs local and do not copy .git, caches or generated Dots state. Dots'
`tools/check_yazi_bundle.py --source /path/to/dots.yazi` checks runtime consistency.
