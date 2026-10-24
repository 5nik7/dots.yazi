# Image and Markdown previews

`dots.preview` owns optional image and Markdown previews. Preview support requires Yazi 26.9.1 or newer. Configure it in the existing `require("dots"):setup({ preview = ... })` call; `require("dots.preview"):setup(...)` also accepts the preview table directly for configurations using only this component.

```lua
preview = {
  image = {
    renderer = "default",
    symbols = "vhalf",
    args = { chafa = {} },
    platforms = { termux = { renderer = "chafa" } },
  },
  markdown = {
    renderer = "mdcat",
    source = "bat",
    args = { mdcat = {}, glow = {}, rich = {}, bat = {}, cat = {} },
    platforms = {
      -- windows = { renderer = "glow", source = "default" },
    },
  },
}
```

Both components default to `renderer = "default"`. Image renderers are `default` (Yazi's existing adapter) and `chafa`; Chafa's `symbols` defaults to `vhalf` and accepts its symbol expressions. The example changes only Termux image rendering. Image cache lookup, delay, preloaders and built-in image/SVG/ImageMagick fallback remain in use. Video and PDF previews are separate.

Markdown renderers are `mdcat`, `glow`, `rich`, `bat` and `default`. Bat displays highlighted Markdown source, not formatted prose. The `source` renderer defaults to `bat` and accepts `bat`, `cat` or `default`. Plain `cat` mode reads text in Lua, needs no external executable, and displays escape characters literally. `default` delegates to Yazi's code preview. Selecting Bat for both modes produces the same presentation.

Supported platform keys are `termux`, `wsl`, `linux`, `macos` and `windows`. Android or a nonempty `TERMUX_VERSION` selects Termux; Linux with `WSL_INTEROP` or `WSL_DISTRO_NAME` selects WSL; otherwise Yazi's target OS is used. Unrecognized OS names use base settings. Resolution is defaults, component options, then matching platform options. Argument lists are replaced, not concatenated; an empty list clears inherited arguments. Unknown options/platforms/renderers and malformed lists are setup errors.

`args` contains optional literal argument lists per executable, for example `args = { mdcat = { "--theme", "dark" }, chafa = { "--colors", "full" } }` in the corresponding component. No shell interprets these arguments. Use tool-specific appearance options only: the adapter reserves width, filenames, rendering format, paging, watch and operational controls. Reserved flags are rejected at setup. `cat` accepts only an empty argument list. Executables are resolved through PATH; no installation or dependency repair occurs.

## Registration and toggle

Add these rules before generic text/image previewers in `yazi.toml`:

```toml
[plugin]
prepend_previewers = [
  { url = "*.{[mM][dD],[mM][aA][rR][kK][dD][oO][wW][nN],[mM][dD][oO][wW][nN]}", run = "dots preview markdown" },
  { mime = "text/{markdown,x-markdown}", run = "dots preview markdown" },
  { mime = "image/{avif,hei?,jxl}", run = "dots preview image magick" },
  { mime = "image/svg+xml", run = "dots preview image svg" },
  { mime = "image/*", run = "dots preview image image" },
]
```

Keep existing fetcher/preloader rules. Markdown extensions match mixed case even when MIME detection reports plain text. Add to `keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on = "<A-m>"
run = "plugin dots -- preview toggle"
desc = "Toggle Markdown preview/source"
```

Alt+m changes the current tab between its configured renderer and source renderer. The choice follows the tab through navigation and reordering; new tabs start rendered and closed-tab state is discarded on the next preview/toggle. Nothing is persisted. Toggling restarts the preview at the top because rendered and source line positions differ. Ordinary preview scrolling works in either mode. On non-Markdown files the command shows a hint without changing state. Theme notifications do not reinitialize preview configuration or tab state.

## Rendering and fallback

External commands run only in asynchronous preview jobs. They emit ANSI text into Yazi's pane at its current width; complete output is parsed before viewport scrolling to preserve styles. Paging, watch modes, terminal probing and inline image protocols are disabled. mdcat uses local resources only and explicitly disables inline images, including when its user configuration selects Kitty. Themes remain owned by each tool's normal configuration/environment; Dots does not install another renderer theme. Tested mdcat is the installed 2.18.0 build supporting `--image-protocol none`.

A missing/failed Markdown renderer falls back to `source`, then built-in code preview, without repeating a renderer. A warning is shown once per failed renderer per session. Empty successful output is valid. Each external invocation has a five-second wall-clock deadline, including waiting for exit after EOF; output over 8 MiB (stdout and stderr together, checked at line boundaries) is rejected and the child is killed. Markdown files larger than 2 MiB go straight to built-in code preview. Yazi cancels obsolete preview jobs; tab/URL/sequence checks also reject stale results before display. The existing built-in fallback keeps its own resource behavior.

Markdown and image preview commands use native executable arguments without Bash/PowerShell wrappers. Native evidence covers Termux only; Windows/WSL/macOS rendering remains pending. Glow and Rich adapters have fixture coverage when their tools are unavailable; that is not native renderer acceptance. See [testing](testing.md).
