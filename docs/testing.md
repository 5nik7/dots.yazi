# Testing

Run from this repository, sequentially:

```sh
lua test.lua
lua test-preview.lua
lua test-color-refs.lua
lua test-git-colors.lua
lua test-githead.lua
lua test-hover.lua
lua test-ls-colors.lua
python3 -B test-ls-colors.py
python3 -B test-native.py
python3 -B test-preview-native.py
python3 -B test-theme-native.py
python3 -B test-package.py
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

The package regression needs Git, ya and Python 3.11+. It reproduces the rejected
skill-directory symlinks, then retries `ya pkg add 5nik7/dots` with real discovery
directories and file symlinks. Both fixture revisions are committed only inside
a disposable repository. Git URL rewriting and `GIT_ALLOW_PROTOCOL=file` keep
the run offline; all home/config/cache/state roots are test-owned. It verifies
all runtime modules, source skill links, the package manifest, refusal of dirty upgrades, clean upgrades and repeated install.

Color-reference fixtures cover fallback, live resolution, explicit false, callback merging and last-good validation. Git style fixtures exercise the installed indicator closure, complete attributes/reset, explicit overrides and hovered-row behavior. Native theme tests use the public reference syntax and both callable getters across refreshes, including malformed optional Git groups.

Preview tests cover platform selection, override/list semantics, literal argv, per-tab state and stale results, output/deadline limits, source fallback, and argument-free seek jobs. The native preview runner owns all config/cache/DDS/TMPDIR roots and accepts `--config-dir` for a copied personal configuration. It requires Yazi, mdcat, Bat and Chafa; Glow/Rich are command fixtures when unavailable. Native tests exercise Alt+m, tab reordering, scrolling, resizing, SVG/PNG and renderer failures. The SVG preloader may report missing optional resvg; direct Chafa SVG rendering is tested independently. Native Windows/WSL/macOS and real Glow/Rich remain separate acceptance checks.
