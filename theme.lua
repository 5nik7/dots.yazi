---@diagnostic disable: undefined-global
-- Published JSON is data. Theme refresh never starts a shell or re-runs setup.
local M = { snapshot = nil }
local options, base, registered, apply_overlay
local function clone(value)
  if type(value) ~= 'table' then return value end
  local result = {}; for k,v in pairs(value) do result[k] = clone(v) end; return result
end
local function merge(a,b)
  local result = clone(a or {})
  for k,v in pairs(b or {}) do
    result[k] = type(v) == 'table' and merge(result[k],v) or v
  end
  return result
end
M.merge = merge
local function color(value)
  return type(value) == 'string' and (value == 'reset' or value:match('^#%x%x%x%x%x%x$'))
end
local attributes = { bold=true, dim=true, italic=true, underline=true, blink=true, blink_rapid=true, reversed=true, hidden=true, crossed=true }
function M.validate(doc)
  assert(type(doc) == 'table' and doc.schema == 1 and type(doc.id) == 'string' and doc.id:match('^[a-z][a-z0-9_%-]*$'), 'unsupported theme snapshot')
  assert(doc.mode == 'dark' or doc.mode == 'light', 'invalid theme mode')
  assert(type(doc.colors) == 'table' and color(doc.colors.background) and color(doc.colors.foreground), 'invalid palette')
  for key,value in pairs(doc.colors) do
    if type(value) ~= 'table' then assert(color(value), 'invalid palette color') end
  end
  assert(type(doc.ls_colors) == 'string' and doc.ls_colors ~= '' and not doc.ls_colors:find('[\n\r\27]'), 'invalid LS_COLORS')
  assert(type(doc.styles)=='table' and type(doc.provenance)=='table', 'missing styles or provenance')
  for _,group in ipairs({'type','mime','extension'}) do
    assert(type(doc.styles[group]) == 'table' and type(doc.colors[group]) == 'table', 'missing style group')
    assert(type(doc.provenance[group])=='table', 'missing style provenance group')
    for key,style in pairs(doc.styles[group]) do
      assert(type(key)=='string' and type(style)=='table','invalid style')
      for field,value in pairs(style) do
        assert((field=='fg' or field=='bg') and color(value) or attributes[field] and type(value)=='boolean','invalid style field')
      end
      assert(color(doc.colors[group][key]), 'invalid color shortcut')
      assert(type(doc.provenance[group][key])=='table', 'missing style provenance')
      for field,source in pairs(doc.provenance[group][key]) do
        assert(type(field)=='string' and type(source)=='string', 'invalid style provenance')
      end
    end
  end
  assert(type(doc.provenance)=='table', 'missing style provenance')
  return doc
end
local function read(path)
  local f = io.open(path, 'rb'); if not f then return nil end
  local data = f:read(2097153); f:close()
  assert(data and #data <= 2097152, 'theme snapshot too large')
  return data
end
local function state_root()
  if options.state then return options.state end
  local root = os.getenv('XDG_STATE_HOME')
  if not root or root == '' then root = (os.getenv('HOME') or '') .. '/.local/state' end
  return root .. '/dots'
end
local function map_colors(value, colors, parent)
  if type(value) ~= 'table' then return value end
  local result = {}
  for k,v in pairs(value) do
    if type(v)=='table' then result[k] = map_colors(v,colors,k)
    elseif type(v)=='string' and (k=='fg' or k=='bg' or k=='color' or tostring(k):match('_color$') or tostring(k):match('_fg$') or parent=='bg_mode') then
      local name = v == 'black' and 'background' or v == 'white' and 'foreground' or v == 'darkgray' and 'muted' or v
      result[k] = type(colors[name])=='string' and colors[name] or v
    else result[k] = v end
  end
  return result
end
local function overlay(doc)
  local result = {}
  for _,component in ipairs({'dotline','hover','githead','hostname_username'}) do
    result[component] = map_colors(base[component] or {}, doc.colors)
  end
  if options.apply then result = merge(result, options.apply(clone(doc.colors),clone(doc.styles)) or {}) end
  for key in pairs(result) do
    assert(key=='dotline' or key=='hover' or key=='githead' or key=='hostname_username', 'theme callback only styles UI components')
  end
  return result
end
function M:refresh()
  if not options or options.source ~= 'dots' then return false end
  local ok, doc, generation, updated = pcall(function()
    local marker = read(state_root() .. '/themes/current')
    if not marker then return end
    local generation = marker:match('^(g%.[%w]+)%s*$')
    assert(generation, 'invalid theme generation')
    if generation == self.generation then return end
    local data = read(state_root() .. '/themes/generations/' .. generation .. '/colors.json')
    if not data then return end
    local doc = M.validate(require('.json').decode(data))
    local updated = overlay(doc)
    return doc, generation, updated
  end)
  if not ok then self.last_error = tostring(doc); return false end
  if not doc then return false end
  if apply_overlay then
    local applied, err = pcall(apply_overlay, updated)
    if not applied then
      if self.current then pcall(apply_overlay, self.current) end
      self.last_error = tostring(err); return false
    end
  end
  require('.ls-colors'):snapshot(doc)
  self.snapshot, self.generation, self.current, self.last_error = doc, generation, updated, nil
  if apply_overlay then ui.render() end
  return true
end
function M:setup(config, initial)
  options, base = config or {}, clone(initial or {})
  self.current, apply_overlay = clone(base), nil
  if options.source ~= 'dots' then self.snapshot = nil; require('.ls-colors'):snapshot(nil) end
  self.generation = nil
  self:refresh()
  if options.source == 'dots' and not registered then
    local function refresh() self:refresh() end
    ps.sub_remote('dots-theme-changed', function(root) if root == state_root() then refresh() end end)
    ps.sub('theme', refresh)
    registered = true
  end
  return merge(base, self.current)
end
function M:bind(callback) apply_overlay = callback end
return M
