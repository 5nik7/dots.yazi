-- Run: lua test-hover.lua. Supply test_plugin and ui to use native Yazi text APIs.
if not ui then
  local function cells(text)
    local n = 0
    for _, c in utf8.codes(text) do n = n + ((c >= 0x3000 and c <= 0x9fff) and 2 or (c == 0x301 and 0 or 1)) end
    return n
  end
  ui = {
    Line = function(s) return { width = function() return cells(s) end } end,
    Text = function(lines) return { max_width = function() return lines[1]:width() end } end,
    truncate = function(s, opts)
      if cells(s) <= opts.max then return s end
      if opts.max == 0 then return "" end
      local chars, out = {}, ""
      for _, c in utf8.codes(s) do chars[#chars + 1] = utf8.char(c) end
      while #chars > 0 do
        local c = table.remove(chars, opts.rtl and #chars or 1)
        if cells(out .. c) > opts.max - 1 then break end
        out = opts.rtl and c .. out or out .. c
      end
      return opts.rtl and "…" .. out or out .. "…"
    end,
  }
end
-- Style adapter follows Yazi's remove=true modifier semantics.
if not ui.Style then
  local methods = {}
  function methods:raw()
    local result = {}
    for k, v in pairs(self.data) do result[k] = v end
    return result
  end
  function methods:patch(other)
    for k, v in pairs(other:raw()) do self.data[k] = v end
    return self
  end
  for _, field in ipairs({ "fg", "bg" }) do
    methods[field] = function(self, value) self.data[field] = value; return self end
  end
  for _, field in ipairs({ "bold", "dim", "italic", "underline", "blink", "blink_rapid", "reverse", "hidden", "crossed" }) do
    methods[field] = function(self, remove) self.data[field == "reverse" and "reversed" or field] = not remove; return self end
  end
  ui.Style = function() return setmetatable({ data = {} }, { __index = methods }) end
end
local saved_require = require
local selected_style = ui.Style():fg("red"):bg("black"):bold()
local target_style = ui.Style():fg("yellow"):bg("blue"):underline()
local directory_style = ui.Style():fg("cyan"):bold()
require = function(module)
  assert(module == ".ls-colors")
  return {
    style = function() return selected_style end,
    target_style = function() return target_style end,
    directory_style = function() return directory_style end,
  }
end
local plugin = test_plugin or dofile("hover.lua")
th = th or { icon = { match = function() return nil end } }
Dotline = { coloreds = { get = {} } }
local family = "unix"
ya = { readable_path = function(s) return s end, target_family = function() return family end }
cx = { active = { current = {} } }
local spans, rendered, renders
local fail = false
local function redraw(self)
  renders = (renders or 0) + 1
  if fail then error("injected redraw failure") end
  spans = Dotline.coloreds.get:hover()
  local texts = {}
  for _, span in ipairs(spans or {}) do texts[#texts + 1] = span[1] end
  rendered = table.concat(texts)
  local left = ui.Text({ ui.Line("tabs: " .. (spans and "[" .. rendered .. "]" or "")) })
  if ui.Rect then left:area(ui.Rect { w = self._area.w, h = 1 }) end
  return { left, ui.Line(" right ") }
end
Header = { redraw = redraw }
Status = { redraw = redraw }
local function cwd(text)
  cx.active.current.cwd = setmetatable({ spec = { is_regular = true } }, { __tostring = function() return text end })
end
local function render(columns, status)
  renders = 0
  local result = (status and Status or Header).redraw({ _area = { w = columns } })
  if columns >= 13 then assert(result[1]:max_width() + result[2]:width() <= columns, rendered) end
  return rendered
end
plugin:setup({ arrow = " -> " })
cwd("/very/long/root/dir")
cx.active.current.hovered = { name = "hovered_name", link_to = "/another/long/root/dir/link" }
assert(render(200) == "/very/long/root/dir/hovered_name -> /another/long/root/dir/link")
assert(renders == 2)
local found = false
for columns = 0, 200 do
  if render(columns) == "../dir/hovered_name -> ../dir/link" then found = true end
end
assert(found, "expected directory-preserving layout")
assert(render(200) == "/very/long/root/dir/hovered_name -> /another/long/root/dir/link")
assert(render(55, true):find("hovered_name", 1, true))
assert(spans[1].style:raw().fg == "cyan" and spans[2].style:raw().fg == "red" and spans[3].style:raw().fg == "darkgray" and spans[4].style:raw().fg == "yellow")
plugin:setup({ arrow = " -> " })
render(100)
assert(renders == 2, "setup must not multiply render wrappers")
cwd("/")
cx.active.current.hovered = { name = "file" }
assert(render(100) == "/file")
cwd("/tmp/")
assert(render(100) == "/tmp/file")
cx.active.current.hovered = nil
assert(render(100) == "/tmp/")
family = "windows"
cwd("C:\\long\\dir")
cx.active.current.hovered = { name = "file", link_to = "C:\\other\\dir\\link" }
for columns = 0, 100 do render(columns) end
assert(render(100) == "C:\\long\\dir\\file -> C:\\other\\dir\\link")
family = "unix"
cwd("/路径/文件夹")
cx.active.current.hovered = { name = "é\nfile", link_to = "/路径/目录/链接" }
for columns = 0, 100 do render(columns) end
assert(render(100) == "/路径/文件夹/é file -> /路径/目录/链接")
fail = true
assert(not pcall(render, 50))
fail = false
assert(Dotline.coloreds.get:hover()[1][1] ~= "")
plugin:setup({ auto_fit = false, path_max_length = 7, path_shorten = false, link_max_length = 7, arrow = " -> " })
cwd("/long/root/dir")
cx.active.current.hovered = { name = "file", link_to = "/long/root/link" }
local values = Dotline.coloreds.get:hover()
assert(values[1][1] == "/long/root/dir/")
assert(values[4][1] .. values[5][1] == "../link")
for _, prefix in ipairs({ "path", "name", "link" }) do
  for _, value in ipairs({ -1, 1.5, "40", math.huge }) do
    assert(not pcall(plugin.setup, plugin, { [prefix .. "_max_length"] = value }))
  end
end
-- Sources and overrides remain independent through fitting and repeated setup.
local function by_part()
  local result = {}
  for _, span in ipairs(spans or {}) do result[span.part] = span end
  return result
end
cwd("/long/root/dir")
cx.active.current.hovered = { name = "file", link_to = "/target", style = function() return ui.Style():fg("magenta") end }
th.icon.match = function() return { text = "ICON", style = ui.Style():fg("green") } end
plugin:setup({ arrow = " -> ", styles = {
  name = { source = "file", bg = "reset", bold = false, italic = true },
  icon = { source = "name", fg = "#123456", reversed = true },
  link = { source = "target", underline = false, fg = 123 },
} })
for columns = 0, 140 do
  render(columns)
  local parts = by_part()
  if parts.name then
    local name, icon, link = parts.name.style:raw(), parts.icon.style:raw(), parts.link.style:raw()
    assert(name.fg == "red" and name.bg == "reset" and name.bold == false and name.italic)
    assert(icon.fg == "#123456" and icon.italic and icon.reversed)
    assert(not name.reversed and link.fg == "123" and link.bg == "blue" and link.underline == false)
    assert(parts.path.style:raw().fg == "cyan" and parts.arrow.style:raw().fg == "darkgray")
  end
end
assert(selected_style:raw().bg == "black" and selected_style:raw().bold)
assert(target_style:raw().fg == "yellow" and target_style:raw().underline)
for _, case in ipairs({
  { {}, "red", "yellow" },
  { { name_color = "green", link_color = "cyan" }, "green", "cyan" },
  { { name_color = "target" }, "yellow", "yellow" },
  { { name_color = "green", theme = { name_color = "blue" } }, "blue", "yellow" },
  { { name_color = "green", theme = { name_color = "blue" }, styles = { name = { italic = true } } }, "red", "yellow" },
  { { styles = { name = { source = "native" }, link = { source = "file" } } }, "magenta", "red" },
  { { styles = { name = { source = "custom", fg = "white" }, link = { source = "custom", bg = "red" } } }, "white", "reset" },
}) do
  plugin:setup(case[1]); render(140)
  local parts = by_part()
  assert(parts.name.style:raw().fg == case[2] and parts.link.style:raw().fg == case[3])
  assert(parts.icon.style:raw().fg == case[2], "icon should inherit the resolved name")
end
plugin:setup({ show_path = false, show_link = false, icon_prefix = "[", icon_suffix = "]", styles = { icon = { source = "icon" } } })
assert(render(140) == "[ICON]file")
assert(by_part().icon.style:raw().fg == "green")
plugin:setup({ show_path = false, show_icon = false, show_link = false })
assert(render(140) == "file")
plugin:setup({ show_name = false, show_icon = false, show_link = false })
assert(render(140) == "/long/root/dir/")
plugin:setup({ show_path = false, show_name = false, show_icon = false, show_link = false })
assert(render(140) == "")
plugin:setup({})
th.icon.match = function() return nil end
render(140)
assert(by_part().icon == nil)
cx.active.current.hovered = nil
assert(render(140) == "/long/root/dir")
assert(by_part().path.style:raw().fg == "cyan")
-- Target directory styling is independent, while fitting keeps the same text.
cx.active.current.hovered = { name = "shortcut", link_to = "../themes/photo.jpg" }
local targets = {
  { "../themes/photo.jpg", "../themes/", "photo.jpg" },
  { "/photo.jpg", "/", "photo.jpg" },
  { "photo.jpg", nil, "photo.jpg" },
  { "/路径/相片.jpg", "/路径/", "相片.jpg" },
  { "../themes/", "../themes/", "" },
  { "/", "/", "" },
}
for _, target in ipairs(targets) do
  cx.active.current.hovered.link_to = target[1]
  plugin:setup({ auto_fit = false, styles = { link_dir = { source = "custom", fg = "blue" } } })
  render(200)
  local parts = by_part()
  assert(parts.link[1] == target[3] and parts.link.style:raw().fg == "yellow")
  if target[2] then
    assert(parts.link_dir[1] == target[2] and parts.link_dir.style:raw().fg == "blue")
  else assert(parts.link_dir == nil) end
end
family = "windows"
cx.active.current.hovered.link_to = "C:\\themes\\photo.jpg"
plugin:setup({ styles = { link_dir = { source = "directory" } } })
render(200)
assert(by_part().link_dir[1] == "C:\\themes\\" and by_part().link[1] == "photo.jpg")
family = "unix"
cx.active.current.hovered.link_to = "/very/long/theme/root/photo.jpg"
local baseline = {}
plugin:setup({ link_max_length = 22 })
for columns = 0, 140 do baseline[columns] = render(columns) end
plugin:setup({ link_max_length = 22, styles = { link_dir = { source = "link", fg = "blue", underline = false } } })
for columns = 0, 140 do
  assert(render(columns) == baseline[columns], "directory styling changed path fitting")
  local parts = by_part()
  if parts.link_dir then
    assert(parts.link_dir.style:raw().fg == "blue" and parts.link_dir.style:raw().underline == false)
    assert(parts.link.style:raw().fg == "yellow" and parts.link.style:raw().underline)
  end
end
plugin:setup({ link_dir_color = "green" }); render(200)
assert(by_part().link_dir.style:raw().fg == "green")
plugin:setup({ styles = { link = { fg = "magenta" } } }); render(200)
assert(by_part().link_dir.style:raw().fg == "magenta", "default directory style must inherit the final link style")
plugin:setup({ show_link = false }); render(200)
assert(by_part().link == nil and by_part().link_dir == nil and by_part().arrow == nil)
for _, options in ipairs({
  { styles = false }, { styles = { typo = {} } }, { styles = { name = "file" } },
  { styles = { name = { source = "icon" } } }, { styles = { name = { source = "typo" } } },
  { styles = { name = { bold = "yes" } } }, { styles = { icon = { typo = true } } },
  { styles = { path = { fg = 256 } } },
}) do assert(not pcall(plugin.setup, plugin, options)) end
require = saved_require
print("dots-hover: layout, style sources, overrides, inheritance, visibility and validation checks passed")
