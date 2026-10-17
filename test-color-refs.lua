-- Theme references resolve before UI use, retain false, and refresh without setup.
local modules = {}
require = function(name)
  if not modules[name] then modules[name]=dofile(name:sub(2)..'.lua') end
  return modules[name]
end
local refs=require('.color-refs')
local theme=require('.theme')
modules['.ls-colors']={snapshot=function() end}
ps={sub=function() end,sub_remote=function() end}
ui={render=function() end}
local colors=refs.namespace(function() return theme.snapshot and theme.snapshot.colors end)
local function doc(bg,repo)
 return {schema=1,id='fixture',mode='dark',ls_colors='di=34',
 colors={background=bg,foreground='#ffffff',git={repo=repo},type={dir='#123456'},mime={},extension={}},
 styles={git={repo={fg=repo,bold=false,bg='reset'}},type={dir={fg='#123456'}},mime={},extension={}},
 provenance={git={repo={fg='fixture'}},type={dir={fg='fixture'}},mime={},extension={}}}
end
local current=doc('#111111','#ab00cd')
local generation='g.first'
modules['.json']={decode=function() return current end}
local open=io.open
io.open=function(path)
 local value=path:match('/current$') and generation or 'snapshot'
 return {read=function() return value end,close=function() end}
end
local config={theme={source='dots'},dotline={style_a={fg=colors.background,reversed=false},custom=colors.type.dir},
 githead={branch_color='#010203',repo_color=colors.git.repo}}
local resolved=theme:setup(config.theme,config)
assert(resolved.dotline.style_a.fg=='#111111' and resolved.dotline.style_a.reversed==false)
assert(resolved.dotline.custom=='#123456' and resolved.githead.repo_color=='#ab00cd')
assert(resolved.githead.repo_owned_color=='yellow' and resolved.githead.branch_color=='#010203')
assert(refs.is(config.dotline.style_a.fg) and colors()==current.colors)
local calls=0
theme:bind(function(value, snapshot)
 calls=calls+1;resolved=value
 assert(snapshot==current)
end)
current=doc('#eeeeee','#120034');generation='g.second'
assert(theme:refresh() and calls==1)
assert(resolved.dotline.style_a.fg=='#eeeeee' and resolved.githead.repo_color=='#120034')
local good=theme.snapshot
current=doc('#111111','#badbad');current.styles.git.repo.bold='bad';generation='g.bad'
assert(not theme:refresh() and theme.snapshot==good and calls==1)
current=doc('#111111','#badbad');current.colors.type.dir=nil;current.styles.type.dir=nil;current.provenance.type.dir=nil;generation='g.missing'
assert(not theme:refresh() and theme.snapshot==good)
assert(theme.last_error:find('unresolved color reference',1,true))
current=doc('#111111','#badbad');generation='g.callback'
local overlaid=theme:setup({source='dots',apply=function()
 return {dotline={style_a={reversed=false,fg='#abcdef'}}}
end},{dotline={style_a={reversed=true,fg=colors.background}}})
assert(overlaid.dotline.style_a.fg=='#abcdef' and overlaid.dotline.style_a.reversed==false)
local retained=theme.snapshot
local applied
theme:bind(function(value, snapshot)
 if snapshot~=retained then error('fixture consumer rejected update') end
 applied=value
end)
current=doc('#eeeeee','#123456');generation='g.rejected'
assert(not theme:refresh() and theme.snapshot==retained and applied==theme.current)
io.open=function() return nil end
local fallback=theme:setup({source='dots'},{githead={repo_color=colors.git.repo,repo_owned_color=colors.git.repo_owned}})
assert(fallback.githead.repo_color=='magenta' and fallback.githead.repo_owned_color=='yellow')
local ok,err=pcall(function() theme:setup({source='dots'},{hover={fg=colors.mime['unknown/custom']}}) end)
assert(not ok and tostring(err):find('unresolved color reference',1,true))
io.open=open
print('PASS color references, defaults, merge, explicit false, refresh and last-good validation')
