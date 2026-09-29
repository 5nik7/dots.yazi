-- Run: lua test-ls-colors.lua. Also used as the resolver bridge by the ls oracle.
local colors = dofile('ls-colors.lua')
local function file(name, fields)
  fields = fields or {}
  fields.perm = function() return fields.permissions or '-rw-r--r--' end
  return { name = name, cha = fields }
end
if arg[1] == '--resolve' then
  local json = dofile('json.lua')
  local cases = json.decode(io.read('*a'))
  local results = {}
  for _, case in ipairs(cases) do
    local e = colors.resolve(colors.parse(case.rules), file(case.name, case.cha))
    results[#results + 1] = e and e.data or {}
  end
  print(json.encode(results))
  return
end
local function match(rules, name, cha)
  return colors.resolve(colors.parse(rules), file(name or 'file', cha)).data
end
assert(colors.parse(nil) == nil and colors.parse('') == nil)
assert(match('di=31:di=34', 'dir', { is_dir = true }).fg == 'blue')
assert(match('*.gz=31:*.tar.gz=32', 'a.tar.gz').fg == 'green')
assert(match('*.tar.gz=32:*.gz=31', 'a.tar.gz').fg == 'red')
assert(match('*.jpg=31', 'a.JPG').fg == 'red')
assert(match('*.jpg=31:*.JPG=32', 'a.JPG').fg == 'green')
assert(match('*.jpg=31:*.JPG=32:fi=33', 'a.JpG').fg == 'yellow')
assert(match('*.jpg=31:*.JPG=31', 'a.JpG').fg == 'red')
assert(match('*.x=31:*.x=0', 'a.x').fg == nil)
assert(match('di=0', 'dir', { is_dir = true }).fg == nil)
assert(match('ex=0:*.x=31', 'a.x', { is_exec = true }).fg == 'red')
local s = match('fi=1;2;3;4;5;6;7;8;9;38;5;123;48;2;1;2;3')
assert(s.fg == 123 and s.bg == '#010203' and s.bold and s.hidden and s.crossed and s.reverse)
s = match('fi=1;2;3;4;5;6;7;8;9;22;23;24;25;27;28;29;31;39;41;49')
assert(next(s) == nil)
assert(next(match('fi=31;1;0')) == nil)
assert(match('fi=97;100').fg == 'white' and match('fi=97;100').bg == 'darkgray')
for _, invalid in ipairs({ '38;5', '38;5;256', '48;2;1;2', '38;3;1', '31oops', '$(touch nope)' }) do
  assert(match('fi=32:fi=' .. invalid).fg == 'green')
end
assert(match('*.a\\:b=31', 'x.a:b').fg == 'red')
assert(match('*.a\\=b=31', 'x.a=b').fg == 'red')
assert(match('*.a\\072b=31', 'x.a:b').fg == 'red')
assert(match('*.a\\x3ab=31', 'x.a:b').fg == 'red')
assert(match('*.a\\\\b=31', 'x.a\\b').fg == 'red')
assert(match('*.a[1]=31', 'x.a[1]').fg == 'red')
assert(match('or=31:ln=32', 'broken', { is_link = true, is_orphan = true }).fg == 'red')
assert(match('ln=target:di=33', 'link', { is_link = true, is_dir = true }).fg == 'yellow')
assert(match('ln=target:ln=32:di=33', 'link', { is_link = true, is_dir = true }).fg == 'green')
assert(match('tw=31:ow=32:st=33', 'dir', { is_dir = true, is_sticky = true, permissions = 'drwxrwxrwt' }).fg == 'red')
assert(match('su=31:sg=32:ex=33', 'exe', { is_exec = true, permissions = '-rwsr-sr-x' }).fg == 'red')
assert(match('mh=31:*.x=32', 'a.x', { nlink = 2 }).fg == 'red')
assert(match('bd=31', 'block', { is_block = true }).fg == 'red')
assert(match('cd=32', 'char', { is_char = true }).fg == 'green')
assert(match('fi=33', 'windows', { permissions = '' }).fg == 'yellow')

-- Native styles are checked by the PTY suite. This fake checks hook/fallback lifecycle.
local fake_style = {}
fake_style.__index = fake_style
function fake_style:patch(other) self.overlay = other; return self end
ui = { Style = function() return setmetatable({}, fake_style) end }
for _, key in ipairs({ 'fg', 'bg', 'bold', 'dim', 'italic', 'underline', 'blink', 'blink_rapid', 'reverse', 'hidden', 'crossed' }) do
  fake_style[key] = function(self, value) self['_' .. key] = value; return self end
end
local native = ui.Style():fg('native')
Entity = { style = function() return native end, icon = function() return 'native-icon' end }
th = { indicator = { current = 'current', preview = 'preview', parent = 'parent' }, icon = { match = function() return { text = 'ICON' } end } }
local getenv = os.getenv
os.getenv = function() return 'fi=31;1' end
colors:setup({ enabled = true })
local hooked = Entity.style
local f = file('a'); f.is_hovered = true; f.in_current = true
local e = { _file = f }
assert(Entity.style(e)._fg == 'red' and Entity.style(e).overlay == 'current')
assert(colors:match(f).overlay == nil, 'cursor patch leaked into base style')
assert(Entity.icon(e) == 'ICON ')
local disabled = colors.to_style({ data = {} })
assert(disabled._fg == 'reset' and disabled._bg == 'reset' and disabled._bold == true)
colors:setup({ enabled = false })
assert(Entity.style == hooked and Entity.style(e) == native and Entity.icon(e) == 'native-icon')
os.getenv = function() return '' end
colors:setup({})
assert(Entity.style(e) == native)
-- Header target mode must not alter the ordinary listing resolver or its rules.
os.getenv = function() return 'ln=36:or=31:di=34:ex=32:*.txt=1;35;43:*.jpg=33' end
colors:setup({})
local link = file('shortcut.jpg', { is_link = true })
link.style = function() return native end
for _, path in ipairs({ '/pictures/photo.txt', '../photo.txt', 'photo.txt' }) do
  link.link_to = setmetatable({ name = 'photo.txt' }, { __tostring = function() return path end })
  local target = colors:target_style(link)
  assert(target._fg == 'magenta' and target._bg == 'yellow' and target._bold == false)
  assert(colors:style(link)._fg == 'cyan', 'target lookup changed symlink listing style')
end
link.cha.is_dir = true
assert(colors:target_style(link)._fg == 'blue')
link.cha.is_dir = false
link.cha.is_exec = true
assert(colors:target_style(link)._fg == 'green')
link.cha.is_exec = false
link.cha.is_orphan = true
assert(colors:target_style(link)._fg == 'red')
link.cha.is_orphan = false
link.cha.is_dummy = true
assert(colors:target_style(link)._fg == 'cyan')
link.cha.is_dummy = false
link.link_to = nil
assert(colors:target_style(link)._fg == 'cyan')
assert(colors:target_style(file('ordinary.jpg'))._fg == 'yellow')
assert(colors:directory_style()._fg == 'blue')
local dir = file('dir', { is_dir = true, is_sticky = true, permissions = 'drwxrwxrwt' })
assert(colors:directory_style(dir)._bg == 'green', 'directory metadata should preserve sticky/write rules')
colors:setup({ enabled = false })
assert(colors:target_style(link) == native)
dir.style = function() return native end
assert(colors:directory_style(dir) == native and colors:directory_style()._fg == 'blue')
os.getenv = function() return '' end
colors:setup({})
assert(colors:target_style(link) == native)
os.getenv = getenv
print('PASS LS_COLORS parsing, precedence, SGR/reset, escapes, hooks and fallback')
