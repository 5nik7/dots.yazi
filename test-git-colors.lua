-- Exercise the installed indicator closure without filesystem or Git activity.
local render, events, modules = nil, {}, {}
local saved_require=require
require=function(name)
 if not modules[name] then modules[name]=dofile(name:sub(2)..'.lua') end
 return modules[name]
end
ya={target_family=function() return 'unix' end,sync=function(fn) return fn end}
ps={sub=function(name,fn) events[name]=fn end}
th={git={}}
local function style()
 local obj={data={}}
 for _,method in ipairs({'fg','bg','bold','dim','italic','underline','blink','blink_rapid','reverse','hidden','crossed'}) do
  obj[method]=function(self,value) self.data[method]=value;return self end
 end
 return obj
end
ui={Style=style,Line=function(parts) return parts end,
 Span=function(text) return {style=function(_,value) return {text=text,style=value.data} end} end}
Linemode={children_add=function(_,fn) render=fn end}
local git=dofile('git.lua')
git:setup({})
git.dirs['/repo']='/repo';git.repos['/repo']={['file']=5}
local file={in_current=true,url=setmetatable({parent='/repo'},{__tostring=function() return '/repo/file' end})}
local function span() return render({_file=file})[2] end
git:recolor({styles={git={modified={fg='#123456',bg='reset',bold=false,italic=true,reversed=false}}}})
local value=span();assert(value.style.fg=='#123456' and value.style.bg=='reset')
assert(value.style.bold==true and value.style.italic==false and value.style.reverse==true)
git:recolor({styles={git={modified={fg='#abcdef',bold=true}}}})
assert(span().style.fg=='#abcdef' and span().style.bold==false)
th.git.unstaged=ui.Style():fg('#010203');events.theme()
assert(span().style.fg=='#010203')
file.is_hovered=true;assert(type(span())=='string','hovered indicator must inherit row style')
file.is_hovered=false;th.git.unstaged_sign='';events.theme();assert(render({_file=file})=='')
require=saved_require
print('PASS Git indicator styles, reset/false attributes, refresh, explicit override and hover behavior')
