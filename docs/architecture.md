# Architecture

`main.lua` installs bundled features once and routes actions without changing their
arguments. Dotline renders headers/status; hover supplies fitted path/link spans;
githead keeps asynchronous Git results separate from command-free rendering.

Githead samples `TMUX` once during setup when `hide_in_tmux` is enabled. Hidden
headers retain empty getters and recoloring closures but install no refresh
subscriptions. Module-level sync guards stop asynchronous jobs before subprocesses
and reject queued results. The independent per-file Git fetcher remains enabled.

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

`color-refs.lua` owns opaque reference tokens and fallback colors. Theme cloning preserves tokens, then resolves them against the validated snapshot before UI application. The callable namespace preserves the snapshot getter API. `git.lua` converts complete Git styles to cached Yazi styles during setup/refresh; its redraw closure performs no I/O. Explicit `th.git` entries take precedence.

This repository owns shared runtime source. For a remote-installed Dots bundle, publish reviewed changes here and update through `ya pkg upgrade 5nik7/dots`. Never manually patch installed files or rewrite package hashes. Keep source-only skills and Git state out of installed runtime. Dots' `tools/check_yazi_bundle.py --source /path/to/dots.yazi` checks runtime consistency after package update.

`preview.lua` owns image/Markdown dispatch and tab-local state, keyed by Yazi's numeric `Id.value`. `preview-config.lua` validates and resolves options without I/O; `preview-process.lua` builds literal argument vectors and bounds asynchronous renderer work. Module-scope sync boundaries snapshot options and validate tab/URL/request identity before displaying results. Preview seek jobs carry no command arguments, so seek uses the tab's last preview kind. Theme refresh leaves this state intact. See [preview behavior](preview.md).
