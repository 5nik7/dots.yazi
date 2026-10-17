--- @since 26.8.15
--- @diagnostic disable: undefined-global

-- Register the pane sync block in the UI context before asynchronous dispatch.
local toggle_pane = require(".toggle-pane")
local palette_theme = require(".theme")
local refresh_theme = ya.sync(function() require(".theme"):refresh() end)

local function setup(_, options)
  options = options or {}
  local theme = require(".theme")
  options = theme:setup(options.theme, options)
  require(".ls-colors"):setup(options.ls_colors or {})
  require(".full-border"):setup(options.full_border or {})
  require(".git"):setup(options.git or {})
  require(".git"):recolor(theme.snapshot)
  require(".folder-rules"):setup(options.folder_rules or {})
  require(".projects"):setup(options.projects or {})
  require(".dotline"):setup(options.dotline or {})
  require(".hover"):setup(options.hover or {})
  require(".githead"):setup(options.githead or {})
  require(".hostname-username"):setup(options.hostname_username or {})
  -- Style updates use existing component state, never the full plugin setup.
  theme:bind(function(value, doc)
    require(".git"):recolor(doc)
    if value.dotline then
      for key,item in pairs(value.dotline) do
        if key ~= 'header_line' and key ~= 'status_line' then Dotline.config[key] = item end
      end
    end
    if value.hover then require('.hover'):setup(value.hover) end
    if value.githead then require('.githead'):recolor(value.githead) end
    if value.hostname_username then require('.hostname-username'):setup(value.hostname_username) end
  end)
end

local function entry(_, job)
  local args = job.args or {}
  local action = args[1]
  if action == "theme-refresh" then refresh_theme(); return end
  local routes = { projects = "projects", githead = "githead", ["toggle-pane"] = "toggle-pane" }
  if not routes[action] then
    return ya.notify({ title = "dots", content = "Unknown action. Use projects or toggle-pane.", level = "warn", timeout = 3 })
  end

  -- Retain named arguments and all other job fields; consume only our route.
  local forwarded = {}
  for key, value in pairs(job) do forwarded[key] = value end
  forwarded.args = {}
  for key, value in pairs(args) do
    if type(key) ~= "number" then
      forwarded.args[key] = value
    elseif key > 1 then
      forwarded.args[key - 1] = value
    end
  end
  if action == "toggle-pane" then
    return toggle_pane:entry(forwarded)
  end
  return require("." .. routes[action]):entry(forwarded)
end

return {
  setup = setup,
  colors = require(".color-refs").namespace(function()
    local doc = palette_theme.snapshot; return doc and doc.colors
  end),
  styles = function() local doc = require(".theme").snapshot; return doc and doc.styles end,
  entry = entry,
  fetch = function(_, job) return require(".git"):fetch(job) end,
}
