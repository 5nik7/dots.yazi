---@diagnostic disable: undefined-global

local context
local hooks = {}

local function width(text)
  return ui.Line(text):width()
end

local function clean(text)
  return tostring(text):gsub("%c", " ")
end

local function option(options, key, fallback)
  if options[key] ~= nil then
    return options[key]
  end
  return fallback
end

local function part(options, prefix, color, max_length, shorten, rtl)
  local theme = options.theme or {}
  local limit = option(options, prefix .. "_max_length", max_length)
  assert(
    type(limit) == "number" and limit >= 0 and limit < math.huge and limit % 1 == 0,
    "dots-hover: " .. prefix .. "_max_length must be a non-negative integer (0 means unlimited)"
  )
  return {
    color = theme[prefix .. "_color"] or options[prefix .. "_color"] or color,
    max_length = limit,
    shorten = option(options, prefix .. "_shorten", shorten),
    rtl = option(options, prefix .. "_rtl", rtl),
  }
end

local attributes = {
  bold = "bold", dim = "dim", italic = "italic", underline = "underline",
  blink = "blink", blink_rapid = "blink_rapid", reversed = "reverse", hidden = "hidden", crossed = "crossed",
}
local sources = { file = true, target = true, directory = true, native = true, custom = true }
local defaults = { path = "directory", name = "file", icon = "name", arrow = "custom", link = "target", link_dir = "link" }
local function inherited_source(key, source)
  return (key == "icon" and (source == "name" or source == "icon")) or (key == "link_dir" and source == "link")
end

local function recipe(options, key)
  local explicit = (options.styles or {})[key]
  local legacy = (options.theme or {})[key .. "_color"] or options[key .. "_color"]
  local result = {}
  if explicit ~= nil then
    assert(type(explicit) == "table", "dots-hover: styles." .. key .. " must be a table")
    for field, value in pairs(explicit) do result[field] = value end
  elseif legacy then
    if sources[legacy] or inherited_source(key, legacy) then
      result.source = legacy
    else
      result.source, result.fg = "custom", legacy
    end
  end
  result.source = result.source or defaults[key]
  assert(sources[result.source] or inherited_source(key, result.source),
    "dots-hover: invalid source for styles." .. key)
  if key == "arrow" and result.source == "custom" and result.fg == nil then result.fg = "darkgray" end
  for field, value in pairs(result) do
    if field == "fg" or field == "bg" then
      assert(type(value) == "string" or (type(value) == "number" and value >= 0 and value <= 255 and value % 1 == 0),
        "dots-hover: " .. key .. "." .. field .. " must be a color string or index (0-255)")
    elseif attributes[field] then
      assert(type(value) == "boolean", "dots-hover: " .. key .. "." .. field .. " must be boolean")
    else
      assert(field == "source", "dots-hover: unknown style option " .. key .. "." .. field)
    end
  end
  return result
end

local function styled(base, config)
  -- Clone with patch before overrides so icon styling cannot mutate its name.
  local s = ui.Style():fg("reset"):bg("reset")
  for _, method in pairs(attributes) do s = s[method](s, true) end
  if base then s = s:patch(base) end
  if config.fg ~= nil then s = s:fg(tostring(config.fg)) end
  if config.bg ~= nil then s = s:bg(tostring(config.bg)) end
  for field, method in pairs(attributes) do
    if config[field] ~= nil then s = s[method](s, not config[field]) end
  end
  return s
end

-- Dotline getters do not receive the line's available width. Measure a render
-- with an empty component (keeping its padding/separators), then render to fit.
local function hook(component)
  if component.redraw == hooks[component] then
    return
  end
  local redraw = component.redraw
  local wrapped = function(self, ...)
    local previous = context
    local frame = { measuring = true, count = 0 }
    context = frame
    local ok, result = pcall(redraw, self, ...)
    if ok and frame.count > 0 then
      local occupied = result[1]:max_width() + result[2]:width()
      frame.measuring = false
      frame.budget = math.floor(math.max(0, self._area.w - occupied) / frame.count)
      ok, result = pcall(redraw, self, ...)
    end
    context = previous
    if not ok then
      error(result, 0)
    end
    return result
  end
  hooks[component] = wrapped
  component.redraw = wrapped
end

-- Candidates drop whole leading directories, retaining the closest directories
-- that fit. Widths strictly decrease so even tiny budgets always terminate.
local function candidates(text, separator, directory)
  local result = { text }
  local function add(value)
    if width(value) < width(result[#result]) then
      result[#result + 1] = value
    end
  end
  local chunks = {}
  for chunk in text:gmatch(separator == "\\" and "[^\\]+" or "[^/]+") do
    chunks[#chunks + 1] = chunk
  end
  for start = 1, #chunks do
    local suffix = table.concat(chunks, separator, start)
    add(".." .. separator .. suffix .. (directory and separator or ""))
  end
  if directory then
    add(".." .. separator)
    add("")
  end
  return result
end

local function item(text, config, variants)
  local values = variants or { text }
  local index = 1
  if config.shorten and config.max_length > 0 then
    while index < #values and width(values[index]) > config.max_length do
      -- Keep the omission marker until the actual window budget requires hiding it.
      if values[index + 1] == "" then
        break
      end
      index = index + 1
    end
    text = values[index]
    if width(text) > config.max_length then
      text = ui.truncate(text, { max = config.max_length, rtl = config.rtl })
    end
  end
  return { text = text, config = config, values = values, index = index }
end

local function next_candidate(value)
  local index = value.index + 1
  while index <= #value.values and width(value.values[index]) >= width(value.text) do
    index = index + 1
  end
  return index <= #value.values and index or nil
end

local function fit(parts, budget)
  local function total()
    local sum = 0
    for _, value in ipairs(parts) do
      sum = sum + width(value.text)
    end
    return sum
  end

  -- Reduce directory context before touching filenames or the arrow.
  while total() > budget do
    local selected, next_index
    for _, value in ipairs(parts) do
      local index = next_candidate(value)
      if index and (not selected or width(value.text) > width(selected.text)) then
        selected, next_index = value, index
      end
    end
    if not selected then
      break
    end
    selected.index = next_index
    selected.text = selected.values[next_index]
  end

  -- Extremely narrow windows may also need shorter filenames. Reduce the
  -- widest text first, preserving the arrow until all other text is exhausted.
  while total() > budget do
    local selected
    for _, value in ipairs(parts) do
      if not value.arrow and width(value.text) > 0 and (not selected or width(value.text) > width(selected.text)) then
        selected = value
      end
    end
    if not selected then
      for _, value in ipairs(parts) do
        if width(value.text) > 0 then
          selected = value
          break
        end
      end
    end
    if not selected then
      break
    end
    local current = width(selected.text)
    local target = math.max(0, current - math.min(total() - budget, math.max(1, math.ceil(current / 2))))
    selected.text = target == 0 and "" or ui.truncate(selected.text, { max = target, rtl = selected.config.rtl })
  end
end

return {
  setup = function(_, options)
    options = options or {}
    local theme = options.theme or {}
    local auto_fit = options.auto_fit ~= false
    local arrow = clean(options.arrow or "  ")
    local arrow_config = { color = theme.arrow_color or options.arrow_color or "darkgray", rtl = false }
    local path = part(options, "path", "blue", 0, true, true)
    local name = part(options, "name", "white", 0, options.shorten ~= false, false)
    local link = part(options, "link", "cyan", options.max_length or 0, options.shorten ~= false, options.rtl ~= false)
    assert(options.styles == nil or type(options.styles) == "table", "dots-hover: styles must be a table")
    local styles = {}
    for key in pairs(options.styles or {}) do assert(defaults[key], "dots-hover: unknown style part " .. key) end
    for key in pairs(defaults) do styles[key] = recipe(options, key) end
    local file_colors = require(".ls-colors")
    local icon_prefix, icon_suffix = clean(options.icon_prefix or " "), clean(options.icon_suffix or " ")

    function Dotline.coloreds.get:hover()
      if auto_fit and context and context.measuring then
        context.count = context.count + 1
        return { { "", "reset" } }
      end
      if auto_fit and context and context.budget == 0 then
        return nil
      end

      local current = cx.active.current
      local cwd = clean(ya.readable_path(tostring(current.cwd)))
      local separator = ya.target_family() == "windows" and current.cwd.spec.is_regular and "\\" or "/"
      local hovered = current.hovered
      local parent = cx.active.parent and cx.active.parent.hovered
      local directory = parent and parent.url == current.cwd and parent or nil
      local icon = hovered and options.show_icon ~= false and th.icon:match(hovered) or nil
      local resolved = {}
      local function resolve(key)
        if resolved[key] then return resolved[key] end
        local config, base = styles[key]
        if config.source == "file" and hovered then base = file_colors:style(hovered)
        elseif config.source == "target" and hovered then base = file_colors:target_style(hovered)
        elseif config.source == "directory" then
          -- Target-parent metadata is not available; use ordinary directory colors.
          local dir = key ~= "link_dir" and directory or nil
          base = file_colors:directory_style(dir)
        elseif config.source == "native" and hovered then base = hovered:style()
        elseif config.source == "name" then base = resolve("name")
        elseif config.source == "link" then base = resolve("link")
        elseif config.source == "icon" and icon then base = icon.style end
        resolved[key] = styled(base, config)
        return resolved[key]
      end
      if hovered and cwd:sub(-1) ~= separator then
        cwd = cwd .. separator
      end
      local paths = candidates(cwd, separator, hovered ~= nil)
      local parts = {}
      local function add(key, value)
        value.style, value.part = resolve(key), key
        parts[#parts + 1] = value
      end
      if options.show_path ~= false then add("path", item(cwd, path, paths)) end
      if hovered then
        if icon and icon.text ~= "" then
          add("icon", item(icon_prefix .. clean(icon.text) .. icon_suffix, { rtl = false, color = name.color }))
        end
        if options.show_name ~= false then add("name", item(clean(hovered.name), name)) end
        if hovered.link_to and options.show_link ~= false then
          add("arrow", { text = arrow, config = arrow_config, values = { arrow }, index = 1, arrow = true })
          local target = clean(ya.readable_path(tostring(hovered.link_to)))
          local target_path = item(target, link, candidates(target, separator, false))
          add("link", target_path)
        end
      end
      if auto_fit and context then
        fit(parts, context.budget)
      end
      local spans = {}
      for _, value in ipairs(parts) do
        -- Fit the target as one path first, preserving existing caps and truncation.
        -- Only then split its directory (including the last separator) from its name.
        local pattern = separator == "\\" and "^(.*[/\\])([^/\\]*)$" or "^(.*/)([^/]*)$"
        local dir, basename
        if value.part == "link" then dir, basename = value.text:match(pattern) end
        if dir then
          spans[#spans + 1] = { dir, "reset", style = resolve("link_dir"), part = "link_dir" }
        end
        spans[#spans + 1] = { basename or value.text, value.config.color, style = value.style, part = value.part }
      end
      return spans
    end

    if auto_fit then
      hook(Header)
      hook(Status)
    end
  end,
}
