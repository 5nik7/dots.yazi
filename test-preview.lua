-- Run sequentially with: lua test-preview.lua
local cfg=dofile('preview-config.lua')
local function fails(fn) assert(not pcall(fn),'expected validation failure') end
local function env(values) return function(k) return values[k] end end
assert(cfg.platform('android',env({}))=='termux')
assert(cfg.platform('linux',env({TERMUX_VERSION='1',WSL_INTEROP='yes'}))=='termux')
assert(cfg.platform('linux',env({WSL_DISTRO_NAME='fixture'}))=='wsl')
assert(cfg.platform('linux',env({TERMUX_VERSION=''}))=='linux')
for _,p in ipairs({'windows','macos','freebsd'}) do assert(cfg.platform(p,env({}))==p) end
fails(function() cfg.resolve(false,"linux") end)
local opts={image={args={chafa={'--colors','full'}},platforms={termux={renderer='chafa',args={chafa={}}}}},markdown={renderer='mdcat',source='cat',platforms={windows={renderer='glow'}}}}
assert(cfg.resolve(opts,'termux').image.renderer=='chafa')
assert(#cfg.resolve(opts,'termux').image.args.chafa==0)
assert(#cfg.resolve(opts,'linux').image.args.chafa==2)
assert(cfg.resolve(opts,'windows').markdown.renderer=='glow')
assert(cfg.resolve(opts,'windows').markdown.source=='cat')
assert(cfg.resolve(nil,'termux').image.renderer=='default')
assert(cfg.resolve(nil,'termux').markdown.renderer=='default')
for _,v in ipairs({{markdown=false},{markdown={renderer='nope'}},{image={source='cat'}},{image={symbols=false}},{markdown={source='glow'}},{image={platforms={android={}}}},{markdown={args={unknown={}}}},{markdown={args={bat={'--paging=always'}}}},{image={args={chafa={'-fsixels'}}}},{markdown={args={mdcat={'--'}}}},{markdown={args={mdcat={[2]='x'}}}}}) do fails(function() cfg.resolve(v,'termux') end) end
for _,name in ipairs({'README.Md','a.MaRkDoWn','test.MDOWN'}) do assert(cfg.markdown({name=name})) end
assert(cfg.markdown({name='README'},'text/markdown'))
assert(not cfg.markdown({name='a.txt'}))

local proc=dofile('preview-process.lua')
local path='/- name 路径.md'
for _,renderer in ipairs({'mdcat','glow','rich','bat','chafa'}) do
 local args=proc.arguments(renderer,{symbols='vhalf',args={}},40,20,path)
 assert(args[#args]==path and args[#args-1]=='--')
end
local calls,notices,widgets,emits={},{},{},{}
local now,behavior=0,'ok'
local fake_command={};fake_command.__index=fake_command
for _,method in ipairs({'stdin','stdout','stderr','env'}) do fake_command[method]=function(self) return self end end
function fake_command:arg(args) self.args=args;return self end
function fake_command:spawn()
 calls[#calls+1]={name=self.name,args=self.args}
 if behavior=='missing' then return nil end
 local mode=behavior
 return {
  read_line_with=function(self)
   if mode=='stale' then cx.active.current.hovered={url='/other'} end
   if mode=='timeout' then now=now+6;return nil,3 end
   if mode=='flood' then return string.rep('x',proc.max_output+1),0 end
   if self.read then return nil,2 end
   self.read=true;return '\27[31mRENDER\27[0m\n',0
  end,
  try_wait=function() if mode=='closed' then return nil end;return {success=mode~='failed'} end,
  start_kill=function(self) self.killed=true end,
 }
end
Command=setmetatable({NULL=0,PIPED=1},{__call=function(_,name) return setmetatable({name=name},fake_command) end})
local builtin_calls={}
local code={peek=function(_,job) builtin_calls[#builtin_calls+1]='code' end,seek=function() builtin_calls[#builtin_calls+1]='seek' end}
local builtin={peek=function() builtin_calls[#builtin_calls+1]='image' end}
local saved_require=require
require=function(name)
 if name=='.preview-config' then return cfg elseif name=='.preview-process' then return proc
 elseif name=='code' then return code elseif name=='image' or name=='svg' or name=='magick' then return builtin end
 return saved_require(name)
end
ya={sync=function(fn)return function(...)return fn({},...)end end,target_os=function()return 'linux'end,
 time=function()return now end,sleep=function(n)now=now+n end,
 notify=function(n)notices[#notices+1]=n end,emit=function(event,args)emits[#emits+1]={event,args} end,
 preview_widget=function(job,w)widgets[#widgets+1]=w end,file_cache=function()return nil end}
local function text(s,ansi)return {text=s,ansi=ansi,area=function(self) return self end,scroll=function(self,x,y)self.skip=y;return self end}end
ui={Text=setmetatable({parse=function(s)return text(s,true)end},{__call=function(_,s)return text(s,false)end})}
Url=function(v)return v end
fs={cha=function()return nil end}
rt={preview={image_delay=0}}
local file={url='/a.md',path='/a.md',name='a.md',cha={len=100}}
local tab1={id={value=1},current={hovered=file}}
local tab2
-- Keep a distinct stable ID even when tabs move to another array position.
tab2={id={value=2},current={hovered=file}}
cx={active=tab1,tabs={tab1}}
local preview=dofile('preview.lua')
preview:setup({markdown={renderer='mdcat'},image={renderer='chafa'}})
local job={file=file,args={'preview','markdown'},area={w=40,h=20},skip=0}
preview:peek(job);assert(calls[#calls].name=='mdcat' and #widgets==1)
preview:entry({args={'toggle'}});assert(emits[#emits][2].force and emits[#emits][2][1]==0)
preview:peek(job);assert(calls[#calls].name=='bat')
cx.active=tab2;cx.tabs={tab2,tab1};preview:peek(job);assert(calls[#calls].name=='mdcat')
cx.active=tab1;preview:peek(job);assert(calls[#calls].name=='bat')
cx.tabs={tab1};preview:peek(job);assert(#preview.tabs==1)
preview:seek({file=file});assert(builtin_calls[#builtin_calls]=='seek')
local old=#emits;tab1.current.hovered={url='/a.txt',name='a.txt'};preview:entry({args={'toggle'}});assert(#emits==old)
tab1.current.hovered=file
preview:setup({markdown={renderer='mdcat',source='bat'}})
preview:entry({args={'toggle'}})
for _,mode in ipairs({'missing','timeout','flood','failed','closed'}) do
 behavior=mode;preview:peek(job);assert(builtin_calls[#builtin_calls]=='code',mode)
end
-- One warning per renderer despite repeated failures.
assert(#notices==3) -- non-Markdown hint plus mdcat and bat failures
behavior='stale';local before=#widgets;preview:peek(job);assert(#widgets==before)
behavior='ok';tab1.current.hovered=file
file.cha.len=proc.max_input+1;local count=#calls;preview:peek(job);assert(#calls==count and builtin_calls[#builtin_calls]=='code');file.cha.len=100
local p=os.tmpname();local f=assert(io.open(p,'wb'));f:write('# SOURCE\27[31m\n');f:close()
file.path=p;preview:setup({markdown={renderer='mdcat',source='cat'}});preview:entry({args={'toggle'}});preview:peek(job)
assert(widgets[#widgets].ansi==false and widgets[#widgets].text:find('%^%['));os.remove(p)
preview:setup({image={renderer='chafa'}});file.path='/a.png';job.args={'preview','image','svg'};preview:peek(job);assert(calls[#calls].name=='chafa')
behavior='failed';preview:peek(job);assert(builtin_calls[#builtin_calls]=='image')
require=saved_require
print('PASS preview configuration, platform precedence, argv, tab state, seek, stale results, resource limits and fallbacks')
