--- @since 26.9.1
-- Configuration and tab state live in the UI VM; all rendering runs asynchronously.
local config = require(".preview-config")
local process = require(".preview-process")
local M = { tabs={}, next_token=0, warned={} }

local function tab_state()
  -- Id.value survives wrapper allocation, tab reordering, and tab switches.
  local alive={}
  for _,entry in ipairs(M.tabs) do
    for _,tab in ipairs(cx.tabs) do
      if entry.id==tab.id.value then alive[#alive+1]=entry;break end
    end
  end
  M.tabs=alive
  for _,entry in ipairs(alive) do if entry.id==cx.active.id.value then return entry end end
  M.next_token=M.next_token+1
  local entry={id=cx.active.id.value,token=M.next_token,source=false,revision=0,sequence=0}
  M.tabs[#M.tabs+1]=entry
  return entry
end

function M:setup(options)
  self.options=config.resolve(options,config.platform(ya.target_os(),os.getenv))
end

local snapshot = ya.sync(function(_, kind, url)
  local file=cx.active.current.hovered
  if not file or file.url~=url then return nil end
  local tab=tab_state()
  tab.sequence=tab.sequence+1
  tab.kind=kind;tab.url=tostring(url)
  if kind=="markdown" then tab.markdown=tostring(url) end
  return {
    options=(M.options or config.resolve(nil,"unknown"))[kind],
    token=tab.token,revision=tab.revision,sequence=tab.sequence,source=tab.source,
  }
end)
local current = ya.sync(function(_, ticket, url)
  local file=cx.active.current.hovered
  if not file or file.url~=url then return false end
  local tab=tab_state()
  return tab.token==ticket.token and tab.revision==ticket.revision and tab.sequence==ticket.sequence
end)
local warn = ya.sync(function(_, renderer, reason)
  if M.warned[renderer] then return end
  M.warned[renderer]=true
  ya.notify({title="dots.preview",content=renderer.." "..reason.."; using the fallback preview.",level="warn",timeout=4})
end)
local toggle = ya.sync(function()
  local tab=tab_state()
  local file=cx.active.current.hovered
  if not file or not (config.markdown(file) or tab.markdown==tostring(file.url)) then
    return ya.notify({title="dots.preview",content="Hover a Markdown file to toggle its preview.",level="info",timeout=2})
  end
  tab.source=not tab.source;tab.revision=tab.revision+1
  ya.emit("peek",{0,force=true,only_if=file.url})
end)
function M:entry(job)
  if job.args[1]=="toggle" then return toggle() end
  ya.notify({title="dots.preview",content="Use preview toggle.",level="warn",timeout=2})
end

local function widget(job, ticket, text, ansi)
  if not current(ticket,job.file.url) then return end
  local value=ansi and ui.Text.parse(text) or ui.Text(text)
  local _,newlines=text:gsub("\n","")
  local bound=math.max(0,newlines+(text:sub(-1)=="\n" and 0 or 1)-job.area.h)
  local skip=math.min(job.skip or 0,bound,65535)
  if skip~=(job.skip or 0) then
    ya.emit("peek",{skip,only_if=job.file.url,upper_bound=true})
  end
  ya.preview_widget(job,value:area(job.area):scroll(0,skip))
end
local function builtin_image(job)
  local name=job.args[3] or "image"
  if name~="image" and name~="svg" and name~="magick" then name="image" end
  return require(name)
end
local function image(job,ticket)
  local builtin=builtin_image(job)
  if ticket.options.renderer=="default" then return builtin:peek(job) end
  local start,url=ya.time(),ya.file_cache(job)
  if not url or not fs.cha(url) then url=Url(job.file.path) end
  ya.sleep(math.max(0,rt.preview.image_delay/1000+start-ya.time()))
  if not current(ticket,job.file.url) then return end
  local text=process.run("chafa",ticket.options,job.area.w,job.area.h,tostring(url))
  if not current(ticket,job.file.url) then return end
  if not text or text=="" then return builtin:peek(job) end
  ya.preview_widget(job,ui.Text.parse(text):area(job.area))
end
local function markdown(job,ticket)
  local opts=ticket.options
  local renderer=ticket.source and opts.source or opts.renderer
  if renderer=="default" or (job.file.cha.len or 0)>process.max_input then
    return require("code"):peek(job)
  end
  local attempted={}
  for _,name in ipairs({renderer,opts.source,"default"}) do
    if not attempted[name] then
      attempted[name]=true
      if not current(ticket,job.file.url) then return end
      if name=="default" then return require("code"):peek(job) end
      local text,reason
      if name=="cat" then text,reason=process.plain(tostring(job.file.path))
      else text,reason=process.run(name,opts,job.area.w,job.area.h,tostring(job.file.path)) end
      if not current(ticket,job.file.url) then return end
      if text~=nil then return widget(job,ticket,text,name~="cat") end
      warn(name,reason)
    end
  end
end
function M:peek(job)
  local kind=job.args[2]
  if kind~="image" and kind~="markdown" then return end
  if job.area.w==0 or job.area.h==0 then return end
  local ticket=snapshot(kind,job.file.url)
  if not ticket then return end
  if kind=="image" then return image(job,ticket) end
  return markdown(job,ticket)
end
function M:seek(job)
  -- Seek jobs do not carry previewer arguments in Yazi 26.9.1.
  local tab=tab_state()
  if tab.kind=="markdown" and tab.url==tostring(job.file.url) then
    return require("code"):seek(job)
  end
  -- Built-in image/SVG/ImageMagick previews have no seek operation.
end
return M
