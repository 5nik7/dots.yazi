--- @since 26.9.1
-- Pure configuration: no filesystem access, commands, or UI state.
local M = {}
local platforms = { termux=true, wsl=true, linux=true, macos=true, windows=true }
local renderers = { image={default=true,chafa=true}, markdown={default=true,mdcat=true,glow=true,rich=true,bat=true} }
local sources = { default=true, bat=true, cat=true }
local defaults = {
  image = { renderer="default", symbols="vhalf", args={chafa={}} },
  markdown = { renderer="default", source="bat", args={mdcat={},glow={},rich={},bat={},cat={}} },
}
-- Extra arguments customize appearance; adapters retain ownership of transport,
-- filenames, width, pagination, and the explicitly named configuration options.
local reserved = {
  chafa={"--format","-f","--symbols","--relative","--probe","--polite","--passthrough","--animate","--view-size","--size","-s","--watch","--files","--files0","--glyph-file","--clear","--duration","-d","--grid","-g","--label","-l","--link"},
  mdcat={"--columns","--full-width","--ansi","--local","-l","--no-pager","-P","--paginate","-p","--watch","-w","--image-protocol","--detect-terminal","--completions","--list-themes"},
  glow={"--width","-w","--pager","-p","--tui","-t"},
  rich={"--width","-w","--force-terminal","--markdown","--pager","-p","--print","--rule","--inspect","--export-html","--export-svg","--export-text","--help-export"},
  bat={"--terminal-width","--paging","--pager","--color","--language","-l","--style","--wrap","--line-range","-r","--list-themes","--list-languages","--config-file","--generate-config-file"},
}
local function copy(v)
  if type(v)~="table" then return v end
  local out={}; for k,x in pairs(v) do out[k]=copy(x) end; return out
end
function M.merge(base, overlay)
  local out=copy(base)
  for k,v in pairs(overlay or {}) do
    if k=="args" then
      out.args=out.args or {}
      for name,args in pairs(v) do out.args[name]=copy(args) end
    elseif k~="platforms" then out[k]=copy(v) end
  end
  return out
end
local function args_ok(name, args)
  assert(type(args)=="table", "preview args must be lists of strings")
  if name=="cat" then assert(next(args)==nil,"preview cat reads plain text and accepts no arguments") end
  local count=0
  for k,arg in pairs(args) do
    count=count+1
    assert(type(k)=="number" and k%1==0 and k>=1 and type(arg)=="string" and not arg:find("%z"),"preview args must be lists of strings")
    assert(arg~="--" and not arg:match("^%-%-?help") and arg~="-h" and arg~="-V" and arg~="--version", "preview args cannot change adapter operation")
    for _,flag in ipairs(reserved[name] or {}) do
      assert(not (arg==flag or arg:sub(1,#flag+1)==flag.."=" or (#flag==2 and arg:sub(1,2)==flag)),"preview adapter owns argument "..flag)
    end
  end
  assert(count==#args,"preview args must be dense lists")
end
local function validate(kind, opts, override)
  assert(type(opts)=="table","preview."..kind.." must be a table")
  for k,v in pairs(opts) do
    if k=="renderer" then assert(renderers[kind][v],"invalid preview."..kind.." renderer")
    elseif k=="source" and kind=="markdown" then assert(sources[v],"invalid preview.markdown source")
    elseif k=="symbols" and kind=="image" then assert(type(v)=="string" and v~="" and not v:find("%z"),"invalid Chafa symbols")
    elseif k=="args" then
      assert(type(v)=="table","preview args must be a table")
      for name,args in pairs(v) do
        assert(defaults[kind].args[name],"unknown preview argument renderer: "..tostring(name)); args_ok(name,args)
      end
    elseif k=="platforms" and not override then
      assert(type(v)=="table","preview platforms must be a table")
      for platform,values in pairs(v) do
        assert(platforms[platform],"unknown preview platform: "..tostring(platform));validate(kind,values,true)
      end
    else error("unknown preview."..kind.." option: "..tostring(k)) end
  end
end
function M.platform(target, getenv)
  local function present(k) local v=getenv(k); return v and v~="" end
  if target=="android" or present("TERMUX_VERSION") then return "termux" end
  if target=="linux" and (present("WSL_INTEROP") or present("WSL_DISTRO_NAME")) then return "wsl" end
  return target
end
function M.resolve(opts, platform)
  if opts==nil then opts={} end
  assert(type(opts)=="table","preview must be a table")
  for k in pairs(opts) do assert(defaults[k],"unknown preview component: "..tostring(k)) end
  local out={}
  for kind,base in pairs(defaults) do
    local values=opts[kind];if values==nil then values={} end;validate(kind,values)
    out[kind]=M.merge(M.merge(base,values),(values.platforms or {})[platform])
  end
  return out
end
function M.markdown(file, mime)
  mime=(mime or ""):lower()
  if mime=="text/markdown" or mime=="text/x-markdown" then return true end
  local name=tostring(file.name or file.url or file.path or ""):lower()
  return name:match("%.md$")~=nil or name:match("%.markdown$")~=nil or name:match("%.mdown$")~=nil
end
return M
