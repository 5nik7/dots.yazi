---@diagnostic disable: undefined-global
-- LS_COLORS is data, never shell code. All parsing happens once at setup.
local M = {}
local rules
local installed = false
local defaults = {
  di = '01;34', ln = '01;36', pi = '33', so = '01;35',
  bd = '01;33', cd = '01;33', ex = '01;32',
  su = '37;41', sg = '30;43', st = '37;44', ow = '34;42', tw = '30;42',
}
local colors = { 'black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'gray',
  'darkgray', 'lightred', 'lightgreen', 'lightyellow', 'lightblue', 'lightmagenta', 'lightcyan', 'white' }
local attributes = { [1] = 'bold', [2] = 'dim', [3] = 'italic', [4] = 'underline',
  [5] = 'blink', [6] = 'blink_rapid', [7] = 'reverse', [8] = 'hidden', [9] = 'crossed' }
local removals = { [22] = { 'bold', 'dim' }, [23] = { 'italic' }, [24] = { 'underline' },
  [25] = { 'blink', 'blink_rapid' }, [27] = { 'reverse' }, [28] = { 'hidden' }, [29] = { 'crossed' } }

local function sgr(value)
  if value:find('[^%d;]') then return nil end
  local codes = {}
  for part in (value .. ';'):gmatch('(.-);') do codes[#codes + 1] = tonumber(part) or 0 end
  local result, i = {}, 1
  while i <= #codes do
    local code = codes[i]
    if code == 0 then result = {}
    elseif attributes[code] then result[attributes[code]] = true
    elseif removals[code] then
      for _, key in ipairs(removals[code]) do result[key] = nil end
    elseif code == 39 then result.fg = nil
    elseif code == 49 then result.bg = nil
    elseif code >= 30 and code <= 37 then result.fg = colors[code - 29]
    elseif code >= 40 and code <= 47 then result.bg = colors[code - 39]
    elseif code >= 90 and code <= 97 then result.fg = colors[code - 81]
    elseif code >= 100 and code <= 107 then result.bg = colors[code - 91]
    elseif code == 38 or code == 48 then
      local key, mode = code == 38 and 'fg' or 'bg', codes[i + 1]
      local count = mode == 5 and 1 or (mode == 2 and 3 or nil)
      if not count then return nil end
      for n = i + 2, i + 1 + count do
        if not codes[n] or codes[n] > 255 then return nil end
      end
      if mode == 5 then result[key] = codes[i + 2]
      else result[key] = string.format('#%02x%02x%02x', codes[i + 2], codes[i + 3], codes[i + 4]) end
      i = i + count + 1
    else return nil end
    i = i + 1
  end
  return result
end

-- Split only on unescaped delimiters, then decode dircolors backslash/caret escapes.
local function split(text, delimiter, first)
  local parts, start, i = {}, 1, 1
  while i <= #text do
    local c = text:sub(i, i)
    if c == '\\' or c == '^' then i = i + 2
    elseif c == delimiter and (not first or #parts == 0) then
      parts[#parts + 1], start, i = text:sub(start, i - 1), i + 1, i + 1
    else i = i + 1 end
  end
  parts[#parts + 1] = text:sub(start)
  return parts
end
local function decode(text)
  local out, i = {}, 1
  local escapes = { a = '\a', b = '\b', e = '\27', f = '\f', n = '\n', r = '\r', t = '\t', v = '\v', ['?'] = '\127', ['_'] = ' ' }
  while i <= #text do
    local c = text:sub(i, i)
    if c == '\\' then
      i = i + 1
      c = text:sub(i, i)
      if c == '' then return nil end
      local digits = text:sub(i):match('^[0-7][0-7]?[0-7]?')
      local hex = c == 'x' and text:sub(i + 1):match('^%x%x?')
      if digits then out[#out + 1], i = string.char(tonumber(digits, 8) % 256), i + #digits
      elseif hex then out[#out + 1], i = string.char(tonumber(hex, 16)), i + 1 + #hex
      else out[#out + 1], i = escapes[c] or c, i + 1 end
    elseif c == '^' then
      local next_char = text:byte(i + 1)
      if not next_char then return nil end
      out[#out + 1], i = string.char(next_char == 63 and 127 or next_char % 32), i + 2
    else out[#out + 1], i = c, i + 1 end
  end
  return table.concat(out)
end

local function entry(value)
  local data = sgr(value)
  return data and { data = data, sequence = value, colored = value ~= '' and value ~= '0' and value ~= '00' }
end
function M.parse(value)
  if not value or value == '' then return nil end
  local parsed = { types = {}, suffixes = {} }
  for key, val in pairs(defaults) do parsed.types[key] = entry(val) end
  for _, pair in ipairs(split(value, ':')) do
    local fields = split(pair, '=', true)
    if #fields == 2 then
      local key, val = decode(fields[1]), decode(fields[2])
      if key and val then
        local e = entry(val)
        if key == 'ln' and val == 'target' then parsed.target = true; parsed.types.ln = nil
        elseif e then
          if key:sub(1, 1) == '*' then
            e.suffix = key:sub(2)
            parsed.suffixes[#parsed.suffixes + 1] = e
          else
            parsed.types[key] = e
            if key == 'ln' then parsed.target = false end
          end
        end
      end
    end
  end
  -- Resolve case collisions in priority order, including older rules shadowed
  -- by an equivalent case-insensitive definition. Work within folded groups.
  local groups, suffixes = {}, {}
  for i = #parsed.suffixes, 1, -1 do
    local e = parsed.suffixes[i]
    e.folded = e.suffix:lower()
    groups[e.folded] = groups[e.folded] or {}
    local group = groups[e.folded]
    group[#group + 1] = e
    suffixes[#suffixes + 1] = e
  end
  for _, group in pairs(groups) do
    for i, e in ipairs(group) do
      if not e.shadowed then
        local folded_match = false
        for j = i + 1, #group do
          local older = group[j]
          if not older.shadowed then
            if e.suffix == older.suffix or folded_match then older.shadowed = true
            elseif e.sequence == older.sequence then
              older.shadowed, folded_match = true, true
            else e.exact, older.exact = true, true end
          end
        end
      end
    end
  end
  parsed.suffixes = {}
  for _, e in ipairs(suffixes) do
    if not e.shadowed then parsed.suffixes[#parsed.suffixes + 1] = e end
  end
  return parsed
end

function M.resolve(parsed, file, as_target)
  if not parsed then return nil end
  local t, cha = parsed.types, file.cha
  local function colored(key) return t[key] and t[key].colored end
  local perm = cha:perm() or ''
  local writable = perm:sub(9, 9) == 'w'
  local kind
  if cha.is_link and (not (as_target or parsed.target) or cha.is_orphan) then
    kind = cha.is_orphan and colored('or') and 'or' or 'ln'
  elseif cha.is_dir then
    kind = cha.is_sticky and writable and colored('tw') and 'tw'
      or writable and colored('ow') and 'ow'
      or cha.is_sticky and colored('st') and 'st' or 'di'
  elseif cha.is_fifo then kind = 'pi'
  elseif cha.is_sock then kind = 'so'
  elseif cha.is_block then kind = 'bd'
  elseif cha.is_char then kind = 'cd'
  else
    kind = perm:sub(4, 4):match('[sS]') and colored('su') and 'su'
      or perm:sub(7, 7):match('[sS]') and colored('sg') and 'sg'
      or cha.is_exec and colored('ex') and 'ex'
      or (cha.nlink or 1) > 1 and colored('mh') and 'mh' or 'fi'
  end
  if kind == 'fi' then
    local name = file.name
    local folded = name:lower()
    for _, e in ipairs(parsed.suffixes) do
      local candidate, suffix = e.exact and name or folded, e.exact and e.suffix or e.folded
      if suffix == '' or candidate:sub(-#suffix) == suffix then return e end
    end
  end
  return t[kind] or t.no or entry('0')
end

function M.to_style(e)
  -- Explicit resets prevent surrounding header/theme styles leaking into a filename.
  local s = ui.Style():fg('reset'):bg('reset')
  if e.data.fg ~= nil then s = s:fg(tostring(e.data.fg)) end
  if e.data.bg ~= nil then s = s:bg(tostring(e.data.bg)) end
  -- Yazi's modifier argument means remove, not enable.
  for _, method in pairs(attributes) do s = s[method](s, not e.data[method]) end
  return s
end
function M:match(file)
  local e = M.resolve(rules, file)
  return e and M.to_style(e) or nil
end
function M:style(file)
  return self:match(file) or file:style() or ui.Style()
end
function M:target_style(file)
  local cha = file.cha
  if rules and cha.is_link and not cha.is_orphan and not cha.is_dummy and file.link_to then
    -- Yazi already carries target metadata; only the displayed basename changes.
    local target = { cha = cha, name = file.link_to.name or file.name }
    return M.to_style(M.resolve(rules, target, true))
  end
  return self:style(file)
end
function M:directory_style(file)
  -- The parent pane may already hold the current directory's metadata. Never stat
  -- ancestors just to color a path; without metadata use the ordinary di category.
  if rules then
    local e = file and M.resolve(rules, file, true) or rules.types.di or rules.types.no or entry('0')
    return M.to_style(e)
  end
  return file and file:style() or ui.Style():fg('blue')
end
function M:setup(options)
  options = options or {}
  rules = options.enabled ~= false and M.parse(os.getenv('LS_COLORS')) or nil
  if installed then return end
  installed = true
  local original_style, original_icon, original_style_rev = Entity.style, Entity.icon, Entity.style_rev
  Entity.style = function(entity)
    local s = self:match(entity._file)
    if not s then return original_style(entity) end
    local file = entity._file
    if not file.is_hovered then return s end
    return s:patch(file.in_current and th.indicator.current or file.in_preview and th.indicator.preview or th.indicator.parent)
  end
  Entity.icon = function(entity)
    local s = self:match(entity._file)
    if not s then return original_icon(entity) end
    local icon = th.icon:match(entity._file, { hovered = entity._file.is_hovered })
    -- Inherit the row's complete style, including its cursor overlay.
    return icon and icon.text .. ' ' or ''
  end
  Entity.style_rev = function(entity)
    if rules then
      local style = entity:style():raw()
      -- Reset means the terminal background, not a foreground for the caps.
      -- Unfilled preview rows should get Yazi's ordinary space padding.
      if style.bg == 'Reset' and not style.reversed then return nil end
    end
    return original_style_rev(entity)
  end
end
return M
