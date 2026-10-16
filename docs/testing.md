# Testing

Run from this repository, sequentially:

```sh
lua test.lua
lua test-githead.lua
lua test-hover.lua
lua test-ls-colors.lua
python3 -B test-ls-colors.py
python3 -B test-native.py
python3 -B test-theme-native.py
```

The Lua cases cover setup/dispatch, async state, hover styles and LS_COLORS
precedence. The Python LS_COLORS check compares against native GNU ls in owned
fixtures. The full native runner uses tests/fixtures/config by default; use
`--config-dir /path/to/dots/config/yazi` to validate an actual source configuration
through a copied, isolated environment. Neither path runs the live configuration
against the owner's home. It requires Yazi, Git and git-it.

The theme runner needs Yazi and ya, and owns its DDS socket/runtime root. It tests
dark/light snapshots, live notification, actual file style, cached MIME/explicit-suffix precedence, N/V/U transitions,
40/80/120-column redraws, malformed-snapshot retention and recovery. Native
Termux evidence does not establish Windows behavior. No test installs dependencies.

Before reporting success, run Lua syntax checks and git diff --check. Verify all
relative Markdown links. Missing tools must be reported as missing checks.
