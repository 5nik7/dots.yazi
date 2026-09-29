# dots.yazi

One local Yazi plugin for the Dots file-manager configuration. It bundles the active UI, Git, project, sorting, and pane features into this directory. **Dotline** is the bundled renderer derived from Yatline; it draws the header and status line.

The original plugin directories are retained for reference, but the active configuration only loads `dots`. This plugin uses its own bundled sources and does not load those originals.

## Installation and setup

Place this entire directory at `plugins/dots.yazi` inside your Yazi configuration directory. Keep the Lua modules and license files together. This is a repository-local plugin; there is no published `ya pkg add` command for it.

The sources declare Yazi 26.8.15 or newer. Native verification uses **Yazi 26.9.1 on Termux**. Git features require the `git` executable. Optional `git-it` supplies remote host icons and configured repository ownership; ordinary Git labels work without it. Icons and separators use the same Nerd Font glyphs as the existing configuration.

Call setup once from `init.lua`:

```lua
require("dots"):setup({
  ls_colors = { enabled = true },
  full_border = { type = ui.Border.PLAIN },
  git = { order = 1500 },
  folder_rules = {
    { name = "Downloads", sort = "mtime", reverse = true, dir_first = false },
  },
  projects = {
    save = { method = "yazi", yazi_load_event = "@projects-load" },
  },
  dotline = {
    header_line = {
      left = {
        section_a = { { type = "line", name = "tabs" } },
        section_b = { { type = "coloreds", name = "hover" } },
        section_c = {},
      },
      right = { section_a = {}, section_b = {}, section_c = {} },
    },
    status_line = {
      left = {
        section_a = { { type = "string", name = "date", params = { "%H:%M" } } },
        section_b = {},
        section_c = {
          { type = "coloreds", name = "githead" },
        },
      },
      right = {
        section_a = {}, section_b = {},
        section_c = { { type = "coloreds", name = "permissions" } },
      },
    },
  },
  hover = {
    auto_fit = true,
    styles = {
      path = { source = "directory" },
      name = { source = "file" },
      icon = { source = "name" },
      arrow = { source = "custom", fg = "darkgray" },
      link_dir = { source = "directory" },
      link = { source = "target" },
    },
  },
  githead = {
    show_remote_icon = true,
    repo_color = "blue",
    repo_owned_color = "green",
    repo_prefix = "", repo_symbol = "",
    branch_color = "magenta", branch_symbol = "",
  },
  hostname_username = { color = "red", mode = "both" },
})
```

The complete personal configuration, including colors, separators, Git indicators, and project events, lives in [init.lua](../../init.lua). Its appearance settings are passed into the plugin, not hardcoded as personal defaults. An omitted section uses that component's defaults. All bundled features initialize; `false` is not a component-disable switch.

## Components and configuration

| Setup section | Bundled module | Behavior and options |
| --- | --- | --- |
| `ls_colors` | [ls-colors.lua](ls-colors.lua) | Reads inherited `LS_COLORS` once at setup; `enabled` defaults to true. Shares full file styles between all file panes and the hovered header name. |
| `full_border` | [full-border.lua](full-border.lua) | Wraps the file panes in borders; `type` selects the border style. |
| `git` | [git.lua](git.lua) | Adds per-file Git indicators; `order` controls their placement. Fetcher rules below are also required. Theme overrides remain in `th.git`. |
| `folder_rules` | [folder-rules.lua](folder-rules.lua) | Applies the first matching rule in an ordered list; each rule accepts `name`, `sort`, `reverse`, and `dir_first`. |
| `projects` | [projects.lua](projects.lua) | Saves, restores, deletes, and merges tab collections; sections are `event`, `save`, `last`, `merge`, and `notify`. |
| `dotline` | [dotline.lua](dotline.lua) | Header/status renderer; preserves Yatline's section, component, separator, padding, style, permission, and layout options. |
| `hover` | [hover.lua](hover.lua) | Registers `hover`, combining the current path, hovered item's Yazi icon and name, and link target; fits whole leading directories to available width. Per-part style sources and overrides control path, name, icon, arrow, target directory, and target basename; the icon inherits the name by default and is omitted when unavailable. |
| `githead` | [githead.lua](githead.lua) | Registers `githead`, one colored component containing repository name and Git details separated by a space; repository options are `show_remote_icon`, `repo_color`, `repo_owned_color`, `repo_prefix`, and `repo_symbol`. Retains branch, remote, tag, commit, ahead/behind, stash, state, staged, unstaged, and untracked options. |
| `hostname_username` | [hostname-username.lua](hostname-username.lua) | Registers `hostname_username`; `mode` accepts `host`, `user`, or `both`, and `color` sets its foreground. Shown only when added to a Dotline section; returns no text on non-Unix platforms. |

[toggle-pane.lua](toggle-pane.lua) is command-driven and needs no setup section. It restores the previous pane ratios when toggled again.

For `folder_rules`, add one table per folder to the list shown above. `name` is a literal directory name, matched at any location when changing directories; rules are checked in order and the first match wins. Omitted options default to `sort = "alphabetical"`, `reverse = false`, and `dir_first = true`. Unmatched folders use those same defaults, as does an empty or omitted rule list. The Downloads rule belongs to `init.lua`, so you can change or remove it there.

### Hover styling and layout

`hover` uses file styles by default, including foreground, background, and text attributes. Configure each part in `hover.styles`:

| Part | Default source | Meaning |
| --- | --- | --- |
| `path` | `directory` | Style the whole current-directory prefix with the directory category. |
| `name` | `file` | Match the hovered file's base listing style, without the cursor overlay. |
| `icon` | `name` | Inherit the resolved name style, including its overrides. |
| `arrow` | `custom` | Use a darkgray foreground and reset background/attributes. |
| `link_dir` | `link` | Inherit the final link style for the target’s directory portion, including its last separator. The personal config selects `directory` instead. |
| `link` | `target` | Style the target basename with its target file’s style. |

Each entry accepts `source`, `fg`, `bg`, and boolean `bold`, `dim`, `italic`, `underline`, `blink`, `blink_rapid`, `reversed`, `hidden`, and `crossed`. Colors accept names, `#RRGGBB`, or indexes 0–255. `fg = "reset"` / `bg = "reset"` clears an inherited color; `false` clears an inherited attribute. Omitted attributes retain the source value. These map to [Yazi styles](https://yazi-rs.github.io/docs/configuration/theme/#style).

Sources available to every part are `file` (shared LS_COLORS/native fallback), `target` (target metadata and basename), `directory` (current directory), `native` (hovered file's Yazi theme style, bypassing LS_COLORS), and `custom` (reset colors/attributes before overrides). For `link_dir` only, `link` inherits the final link style, including overrides. For the icon only, `name` inherits the final name style and `icon` selects the native icon theme style. For example:

```lua
hover = {
  styles = {
    name = { source = "file", bg = "reset", bold = false },
    icon = { source = "name", fg = "#89b4fa" },
    path = { source = "directory", dim = true },
    link_dir = { source = "custom", fg = "blue" },
    link = { source = "target", underline = true },
    arrow = { source = "custom", fg = 244 },
  },
}
```

This keeps file-derived foreground colors, removes the name's background/bold, colors only its icon blue, dims the directory prefix, colors the target directory blue, and underlines the target basename. Overrides never mutate the file-pane style or another part. Use `source = "custom"` for a completely fixed style. Unknown parts, sources, or style fields produce a setup error instead of being silently ignored.

`styles.<part>` takes precedence over the corresponding legacy `<part>_color` option. If that style entry is absent, `theme.<part>_color` wins over `<part>_color`; otherwise the defaults above apply. An explicit entry such as `styles.name = { italic = true }` starts from the default file source, ignoring legacy name colors. Older `name_color = "file"`, `name_color = "target"`, `link_color = "target"`, and literal colors remain supported. Literal legacy colors select a fixed foreground with reset background/attributes. Avoid mixing both configuration styles for the same part.

`show_path`, `show_name`, `show_icon`, and `show_link` default to true and independently control visibility. Hiding the target also hides its directory portion and arrow. The icon's `icon_prefix` and `icon_suffix` each default to one space and can be changed or emptied. The icon is omitted when no match exists. `arrow` changes the link connector text.

For fitting, `path_*`, `name_*`, and `link_*` accept `max_length`, `shorten`, and `rtl` suffixes. A maximum length of `0` means unlimited; `name_max_length` now applies to the filename separately from its icon. `auto_fit` defaults to true and reduces directory context before truncating names. Control characters in paths, icons, spacing and arrow text are sanitized for single-line display.

`link_dir` supports the same color/attribute overrides and legacy `link_dir_color` option as the other parts. For `../themes/photo.jpg`, it styles `../themes/` and `link` styles `photo.jpg`. With no directory in the target there is no `link_dir` span. A trailing separator belongs to the directory portion. The target is fitted as one path before splitting its styles, so `link_max_length`, `link_shorten`, and `link_rtl` still apply to the entire target.

The directory prefix uses current-directory metadata already available in the parent pane, or the ordinary `di` category when unavailable. With LS_COLORS disabled it uses the native directory file style, or blue when that metadata is unavailable. `link_dir.source = "directory"` uses the ordinary directory category because target-parent metadata is unavailable; it adds no filesystem lookup. It colors each directory portion as one part; it does not inspect every ancestor. No filesystem lookups or subprocesses are added to redraws.

### LS_COLORS styling

`ls_colors = { enabled = true }` reads the environment Yazi inherits; it never runs `ls`, Vivid, or shell code during rendering. Restart Yazi after shell theme changes. This reads `LS_COLORS`; it does not parse eza-specific theme files or `EZA_COLORS`. An unset/empty variable or `enabled = false` retains native Yazi file styles. The source integration survives Dots theme refresh without changing generated flavor files.

The personal configuration uses the default `styles.name.source = "file"` and `styles.link.source = "target"`: the hovered icon/name retains its own file or symlink style, while the basename after the arrow uses the target’s actual style and `styles.link_dir.source = "directory"` colors its directory portion. For example, `shortcut  ~/Pictures/photo.jpg` renders `shortcut` with the symlink style and `photo.jpg` with the `.jpg` style, and `~/Pictures/` with the directory style. The directory prefix, icon, and arrow have independent style entries.

Target matching uses the target basename and metadata Yazi already supplies, without filesystem probes or link-chain traversal. Broken links, unavailable target metadata, or disabled/unset LS_COLORS fall back to the existing file style. Use `styles.name.source = "target"` to apply the target style to the hovered name, or `source = "custom"` with explicit colors to replace it. Header styling does not change file-pane matching.

Cursor indicators are layered over the file-pane style. Preview rows with a reset background and no reverse highlight use ordinary space padding, preventing `█` caps from appearing in the terminal’s default foreground. Rows with an explicit or reversed highlight retain colored caps. Search highlights, selection markers, and Git decorations retain their own styles.

Matching follows GNU ls file-category precedence and ordered literal suffix rules (later definitions win, including overlapping suffixes). Case-collision processing follows GNU ls: equivalent differently cased rules can shadow older definitions; surviving differently styled variants match exact case. Regular files, directories, executable and permission-based categories, symlinks/broken links, FIFOs, sockets, devices, and hard links use Yazi's existing metadata. `ln=target` uses the target metadata Yazi already supplies and the displayed link name. No filesystem probes are added. Linux capability (`ca`) and Solaris door (`do`) detection are unsupported; those files use the applicable ordinary category. Unix permission/hard-link rules apply only where metadata is available.

ANSI, indexed, and RGB foreground/background colors and bold, dim, italic, underline, blink, rapid blink, reverse, hidden, and crossed-out attributes are supported, including resets/removal codes. Missing category definitions use GNU ls defaults. Explicit empty/zero styles reset the file style; zero-valued special categories such as `ex=0` disable that category's priority, as in GNU ls. Malformed entries and unsupported SGR sequences are ignored independently. Terminal-control wrappers (`lc`, `rc`, `ec`, `cl`, `rs`) are not executed or used to alter the UI. Filenames remain sanitized independently of styling.

### Dotline extensions

Bundled components register against `Dotline.string`, `Dotline.line`, and `Dotline.coloreds`, replacing the old `Yatline` global. Colored entries retain the `{ text, color }` format and optionally accept a `style` field containing a Yazi `ui.Style`; that full style replaces the component style for that span. Component names include `tabs`, `permissions`, `repo_name`, `hover`, and `githead`. The hovered-path component now uses `hover.lua`, the `hover` setup table, and the `hover` colored getter; update those names together in custom configurations. Add custom getters after setup, for example:

```lua
function Dotline.string.get:greeting()
  return "hello"
end
```

Reference that getter with `{ type = "string", name = "greeting" }` in a section. External Yatline extensions must be adapted to `Dotline`; there is no `Yatline` compatibility alias. Do not initialize the old renderer or extensions alongside `dots`.

## Commands and keymaps

The first argument after `--` selects the feature; remaining arguments are forwarded to it. For example:

```toml
[[mgr.prepend_keymap]]
on = ["P", "s"]
run = "plugin dots -- projects save"
desc = "Save current project"

[[mgr.prepend_keymap]]
on = ["<C-x>"]
run = "plugin dots -- toggle-pane min-preview"
desc = "Show or hide the preview pane"
```

The current [keymap](../../keymap.toml) uses these routes:

| Keys | Command |
| --- | --- |
| `Ctrl-x` | `plugin dots -- toggle-pane min-preview` |
| `X` | `plugin dots -- toggle-pane max-preview` |
| `P s` | `plugin dots -- projects save` |
| `P l` | `plugin dots -- projects load` |
| `P P` | `plugin dots -- projects load_last` |
| `P d` | `plugin dots -- projects delete` |
| `P D` | `plugin dots -- projects delete_all` |
| `P m` | `plugin dots -- projects merge current` |
| `P M` | `plugin dots -- projects merge all` |

Load or delete by saved key or name by appending it, e.g. `plugin dots -- projects load 'My project'`. Save/load/delete retain the existing interactive selection and cancellation behavior. `delete_all` immediately clears the saved project list, as in the original plugin. Unknown feature routes produce a warning. The `githead` route refreshes both repository naming and Git status internally.

### Git fetchers

Use these rules in `yazi.toml` for both files and directories:

```toml
[[plugin.prepend_fetchers]]
id = "git"
url = "*"
run = "dots"
group = "git"

[[plugin.prepend_fetchers]]
id = "git"
url = "*/"
run = "dots"
group = "git"
```

Repository-name options live in the `githead` setup section; there is no separate `repo` section or module. Use only `{ type = "coloreds", name = "githead" }` in the section: it renders `󰊤 dots main !169 ?24` for a GitHub remote as one group, with no Dotline part separator between the repository and branch. The `repo_name` getter remains available for repository-only displays; adding it alongside `githead` would repeat the name. Both share one refresh generation, and results from an older request or directory are discarded.

`show_remote_icon` defaults to true. The icon appears before `repo_prefix .. repo_symbol .. name`, separated by one space, and shares the repository name color. `repo_color` defaults to blue; `repo_owned_color` defaults to that same color when omitted. The personal config sets owned repositories to green. Both color options can also live in the existing `theme` table. Hiding the icon leaves ownership coloring enabled. Branch and status colors remain independent.

Each existing asynchronous Git refresh runs one local `git-it info --json` command to obtain the icon and ownership together. Rendering runs no commands. The plugin follows git-it's remote selection (branch remote, then origin), host aliases, and configured owners. GitHub, GitLab, and Bitbucket have host icons; unknown hosts and repositories without a remote use git-it's generic Git icon. Missing git-it, failed commands, or malformed metadata omit the icon and use the normal repository color. Only the validated icon and ownership boolean are retained, and both are cleared with the Git status when navigating.

Ownership means an exact configured host/namespace match, not authentication or write access. Configure git-it separately in `${XDG_CONFIG_HOME:-$HOME/.config}/git-it/config`, for example:

```gitconfig
[git-it]
    owner = github.com/your-name
    owner = gitlab.com/your-team/subgroup
    hostAlias = github-work=github.com
```

This plugin never changes that configuration or contacts the remote. The optional Bash-based git-it helper must be executable on the host; native Windows integration has not been verified.

The dispatcher forwards fetch jobs to the bundled Git module. These rules keep the configuration's existing matching, IDs, and grouping. A single combined repository/Git-head refresh responds to directory, tab, rename, bulk, move, trash, and delete events.

## Project storage and runtime

`projects.save.method = "yazi"` retains Yazi DDS persistence through `@projects-load`. Existing project data and event names are unchanged; this consolidation requires no data migration. Save/load/delete/delete-all/merge notifications still use the `project-saved`, `project-loaded`, `project-deleted`, `project-deleted-all`, and `project-merged` events. Cross-instance merge uses `projects-merge`.

For JSON file storage, set `save.method = "lua"` and a writable `save.lua_save_path`. If that path is omitted from the `save` table, the existing fallback is `%APPDATA%/yazi/state/projects.json` on Windows or `~/.local/state/yazi/projects.json` on Unix. The plugin does not create missing parent directories. The current personal config has an empty path because it uses DDS; replace that value when switching to file storage.

`main.lua` performs setup and dispatch. Each relative module has separate Yazi-managed state (for example, `dots.projects` and `dots.git`). Dotline initializes before its additional getters. Project prompts and Git commands run asynchronously; their state updates and pane ratio changes cross into the UI context using `ya.sync`.

The merged upstream packages have been removed from [package.toml](../../package.toml). Unrelated installed plugins remain separate. Updates to these bundled sources are maintained in Dots rather than through the original package entries.

## Verification

From this directory:

```sh
lua test.lua
lua test-githead.lua
lua test-hover.lua
lua test-ls-colors.lua
python3 -B test-ls-colors.py
python3 -B test-native.py
```

The Lua fixtures check setup order, dispatcher arguments, fetch forwarding, pane restoration, combined Git refresh/stale-result rejection, host metadata validation and failure fallbacks, independent repository/branch colors, command-free redraws, responsive hover formatting, per-part sources/overrides/visibility and style isolation, and LS_COLORS parsing, precedence, resets, and hook fallback. The GNU ls comparison runner uses disposable filesystem fixtures and reports unsupported native hard-link creation separately; its matching remains covered by Lua fixtures. The Unix PTY test uses the surrounding repository's actual config without replacing its hover settings and a temporary home/config/state/cache/runtime, isolated Git repository, and DDS socket directory. Only `dots.yazi` and a test probe are installed there. It checks real loader state, Git fetching and callbacks, installed git-it host/ownership rendering with test-owned GitHub/GitLab/Bitbucket/unknown/no-remote fixtures and host aliases, project save/load/deletion and merge event dispatch, folder rules, pane shortcuts, ANSI/indexed/RGB styles, separate symlink/target styles, reset-background preview spacing, filled cursor caps, native-style fallback, independent icon overrides, attribute removal, current-directory styling, and 40/80/160-column redraws. It requires Python, Git, git-it, and Yazi and does not install dependencies.

Native results currently cover Termux with Yazi 26.9.1. Lua Windows-path fixtures are not native Windows verification. The PTY checks establish successful rendering without errors, not pixel-perfect visual equivalence.

## Attribution

Dotline is derived from [Yatline](https://github.com/5nik7/yatline.yazi). Other bundled sources come from [yazi-rs/plugins](https://github.com/yazi-rs/plugins) (full-border, git, toggle-pane), [MasouShizuka/projects.yazi](https://github.com/MasouShizuka/projects.yazi), [imsi32/yatline-githead.yazi](https://github.com/imsi32/yatline-githead.yazi), and [jaja360/yatline-hostname-username.yazi](https://github.com/jaja360/yatline-hostname-username.yazi). Folder rules, repository naming, and responsive symlink integration come from the existing Dots configuration.

Original notices are retained in [licenses/](licenses/), including the Projects JSON helper's inline notice. Dots changes use the repository's [MIT license](LICENSE).
