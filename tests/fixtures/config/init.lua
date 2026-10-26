require("dots"):setup({
  preview = {
    image = { renderer = "default", symbols = "vhalf", args = { chafa = {} },
      platforms = { termux = { renderer = "chafa" } } },
    markdown = { renderer = "mdcat", source = "bat",
      args = { leaf = {}, mdcat = {}, glow = {}, rich = {}, bat = {}, cat = {} }, platforms = {} },
  },
  theme = {
    source = "dots",
    apply = function(colors)
      return { dotline = {
        style_a = { fg = colors.background, reversed = false,
          bg_mode = { normal = colors.blue, select = colors.magenta, un_set = colors.red } },
        style_b = { fg = colors.foreground, bg = colors.background },
        style_c = { fg = colors.foreground, bg = colors.background },
      } }
    end,
  },
  full_border = {
    -- Available values: ui.Border.PLAIN, ui.Border.ROUNDED
    type = ui.Border.PLAIN,
    -- type = ui.Border.DOUBLE,
  },

  git = {
    order = 1500,
  },

  folder_rules = {
    { name = "Downloads", sort = "mtime", reverse = true, dir_first = false },
  },

  projects = {
    event = {
      save = {
        enable = true,
        name = "project-saved",
      },
      load = {
        enable = true,
        name = "project-loaded",
      },
      delete = {
        enable = true,
        name = "project-deleted",
      },
      delete_all = {
        enable = true,
        name = "project-deleted-all",
      },
      merge = {
        enable = true,
        name = "project-merged",
      },
    },
    save = {
      method = "yazi", -- yazi | lua
      yazi_load_event = "@projects-load", -- event name when loading projects in `yazi` method
      lua_save_path = "", -- path of saved file in `lua` method, comment out or assign explicitly
      -- default value:
      -- windows: "%APPDATA%/yazi/state/projects.json"
      -- unix: "~/.local/state/yazi/projects.json"
    },
    last = {
      update_after_save = true,
      update_after_load = true,
      update_before_quit = false,
      load_after_start = false,
    },
    merge = {
      event = "projects-merge",
      quit_after_merge = false,
    },
    notify = {
      enable = true,
      title = "Projects",
      timeout = 3,
      level = "info",
    },
  },

  dotline = {
    section_separator = { open = "", close = "" },
    inverse_separator = { open = "", close = "" },
    part_separator = { open = "", close = "" },

    padding = { inner = 1, outer = 1 },

    style_a = {
      fg = "black",
      bold = true,
      underline = false,
      reversed = true,
      bg_mode = {
        normal = "blue",
        select = "magenta",
        un_set = "red",
      },
    },
    style_b = { bg = "black", fg = "white" },
    style_c = { bg = "black", fg = "white" },

    permissions_t_fg = "black",
    permissions_r_fg = "yellow",
    permissions_w_fg = "red",
    permissions_x_fg = "green",
    permissions_s_fg = "black",

    tab_width = 0,

    selected = { icon = "󰻭", fg = "yellow" },
    copied = { icon = "", fg = "green" },
    cut = { icon = "", fg = "red" },

    files = { icon = "", fg = "blue" },
    filtereds = { icon = "", fg = "magenta" },

    total = { icon = "󰮍", fg = "yellow" },
    success = { icon = "", fg = "green" },
    failed = { icon = "", fg = "red" },

    show_background = true,

    display_header_line = true,
    display_status_line = true,

    component_positions = { "header", "tab", "status" },

    header_line = {
      left = {
        section_a = {
          { type = "line", name = "tabs" },
        },
        section_b = {},
        section_c = {},
      },
      right = {
        section_a = {},
        section_b = {
          { type = "coloreds", custom = false, name = "githead" },
        },
        section_c = {},
      },
    },

    status_line = {
      left = {
        section_a = {
          { type = "string", name = "mode_letter" },
        },
        section_b = {

          { type = "coloreds", custom = false, name = "hover" },
        },
        section_c = {},
      },
      right = {
        section_a = {},
        section_b = {},
        section_c = {
          { type = "coloreds", name = "permissions" },
        },
      },
    },
  },

  hover = {
    auto_fit = true,
    show_path = true,
    show_name = true,
    show_icon = true,
    show_link = true,
    icon_prefix = " ",
    icon_suffix = " ",
    styles = {
      path = { source = "directory" },
      name = { source = "file" },
      icon = { source = "name" },
      arrow = { source = "custom", fg = "darkgray" },
      link_dir = { source = "directory" },
      link = { source = "target" },
      -- Add fg/bg or attributes to any part, e.g. name = { source = "file", bg = "reset", bold = false }.
    },
    path_max_length = 0,
    path_shorten = true,
    path_rtl = true,
    name_max_length = 0, -- 0 means unlimited.
    name_shorten = true,
    name_rtl = false,
    arrow = "  ",
    link_max_length = 0,
    link_shorten = true,
    link_rtl = true,
  },

  githead = {
    hide_in_tmux = false, -- Set true to hide the group and skip its queries in tmux.
    show_remote_icon = true,
    repo_color = "blue",
    repo_owned_color = "green",
    repo_prefix = "", -- Literal text; include any desired trailing space.
    repo_symbol = "", -- Optional icon; i
    order = {
      "branch",
      "remote",
      "tag",
      "commit",
      "behind_ahead_remote",
      "stashes",
      "state",
      "staged",
      "unstaged",
      "untracked",
    },

    show_numbers = true, -- shows staged, unstaged, untracked, stashes count

    show_branch = true,
    branch_prefix = "",
    branch_color = "magenta",
    branch_symbol = "",
    branch_borders = "",

    show_remote_branch = true, -- only shown if different from local branch
    always_show_remote_branch = false, -- always show remote branch even if it the same as local branch
    always_show_remote_repo = false, -- Adds `origin/` if `always_show_remote_branch` is enabled
    remote_branch_prefix = ":",
    remote_branch_color = "magenta",

    show_tag = true, -- only shown if branch is not available
    always_show_tag = false,
    tag_color = "magenta",
    tag_symbol = "#",

    show_commit = true, -- only shown if branch AND tag are not available
    always_show_commit = false,
    commit_color = "magenta",
    commit_symbol = "@",

    show_behind_ahead_remote = true,
    behind_remote_color = "magenta",
    behind_remote_symbol = "⇣",
    ahead_remote_color = "magenta",
    ahead_remote_symbol = "⇡",

    show_stashes = true,
    stashes_color = "darkgray",
    stashes_symbol = "$",

    show_state = true,
    show_state_prefix = true,
    state_color = "red",
    state_symbol = "~",

    show_staged = true,
    staged_color = "cyan",
    staged_symbol = "+",

    show_unstaged = true,
    unstaged_color = "cyan",
    unstaged_symbol = "!",

    show_untracked = true,
    untracked_color = "cyan",
    untracked_symbol = "?",
  },

  hostname_username = {
    color = "red",
    mode = "both", -- "host", "user", "both"
  },
})

function Dotline.string.get:mode_letter()
  local mode = cx.active.mode
  if mode.is_select then
    return "V"
  elseif mode.is_unset then
    return "U"
  end
  return "N"
end
