-- Run from this directory: lua test-githead.lua
local json = dofile("json.lua")
local original_require = require
require = function(name) return name == ".json" and json or original_require(name) end
local urls = {}
Url = function(path)
  if not urls[path] then
    urls[path] = setmetatable({ name = path:match("[^/]+$"), spec = { is_regular = true } },
      { __tostring = function() return path end })
  end
  return urls[path]
end
local cwd = "/fixture with spaces/-repo 路径"
local head, subscriptions, save, calls, response, during_output, emitted
local original_getenv = os.getenv
local tmux
os.getenv = function(name)
  if name == "TMUX" then return tmux end
  return original_getenv(name)
end
local function output(text, success)
  return { stdout = text, status = { success = success ~= false } }
end
Command = setmetatable({ PIPED = "pipe", NULL = "null" }, { __call = function(_, program)
  local cmd = { program = program }
  for _, method in ipairs({ "arg", "cwd", "stdout", "stderr", "env" }) do
    cmd[method] = function(self, value) self["_" .. method] = value; return self end
  end
  function cmd:output()
    calls[#calls + 1] = self
    assert(self._cwd == cwd)
    if program == "git-it" then
      assert(table.concat(self._arg, " ") == "info --json")
      assert(self._stdout == Command.PIPED and self._stderr == Command.NULL)
      if during_output then during_output() end
      return response
    end
    if self._arg[2] == "--show-toplevel" then return output(cwd .. "\n") end
    if self._arg[1] == "status" then return output("On branch main\nnothing to commit, working tree clean\n") end
    return output("", false)
  end
  return cmd
end })
local function setup(options)
  subscriptions, calls, during_output, emitted = {}, {}, nil, 0
  cx = { active = { current = { cwd = Url(cwd) } } }
  Dotline = { coloreds = { get = {} } }
  ui = { render = function() end }
  ps = { sub = function(event, fn) subscriptions[event] = fn end }
  ya = {
    sync = function(fn) save = fn; return function(...) return fn(head, ...) end end,
    quote = function(s) return s end, emit = function() emitted = emitted + 1 end,
  }
  head = dofile("githead.lua")
  head._id = "dots.githead"
  head:setup(options or {})
  if subscriptions.cd then subscriptions.cd() end
end
local function refresh(info)
  response = info
  head:entry({ args = { cwd, tostring(head.request) } })
end
local function label(text, color)
  local before = #calls
  for _, getter in ipairs({ "repo_name", "githead" }) do
    local spans = Dotline.coloreds.get[getter]()
    assert(spans[1][1] == text, spans[1][1])
    assert(spans[1][2] == color, tostring(spans[1][2]))
  end
  assert(#calls == before, "rendering spawned a process")
end
setup({ repo_color = "blue", repo_owned_color = "green", branch_symbol = "", branch_color = "magenta" })
for _, fixture in ipairs({
  { "󰊤", true, "green" }, { "", false, "blue" }, { "", true, "green" }, { "", false, "blue" },
}) do
  refresh(output(json.encode({ icon = fixture[1], owned = fixture[2], url = "unused", host = "unused" })))
  label(fixture[1] .. " -repo 路径", fixture[3])
  assert(head.repo_info.url == nil and head.repo_info.host == nil)
end
local helper_calls = 0
for _, cmd in ipairs(calls) do if cmd.program == "git-it" then helper_calls = helper_calls + 1 end end
assert(helper_calls == 4, "expected exactly one metadata command per refresh")
-- Branch/status text and colors are identical with and without metadata.
local data = { branch = "main", unstaged = "a\nb\n", untracked = "c\n" }
save(head, cwd, head.request, "dots", data)
local plain = Dotline.coloreds.get.githead()
save(head, cwd, head.request, "dots", data, { icon = "󰊤", owned = true })
local decorated = Dotline.coloreds.get.githead()
assert(#plain == #decorated)
for i = 2, #plain do assert(plain[i][1] == decorated[i][1] and plain[i][2] == decorated[i][2]) end
local text = {}
for _, span in ipairs(decorated) do text[#text + 1] = span[1] end
assert(table.concat(text) == "󰊤 dots main !2 ?1")

-- Every failure replaces previously valid metadata, without affecting Git status.
local invalid = { "invalid json", "null", "true", "[]", "{}", '{"icon":5,"owned":true}',
  '{"icon":"x","owned":"true"}', '{"icon":"x"}', '{"icon":"","owned":true}',
  string.rep(" ", 65537) }
for _, body in ipairs(invalid) do
  refresh(output('{"icon":"󰊤","owned":true}'))
  refresh(output(body))
  label("-repo 路径", "blue")
  assert(head.repo_info == nil and head.output.branch == "main")
end
refresh(output('{"icon":"󰊤","owned":true}', false))
label("-repo 路径", "blue")
refresh(nil) -- Missing executable.
label("-repo 路径", "blue")
refresh(output('{"icon":"\\n󰊤\\t\\r","owned":true}'))
label("󰊤 -repo 路径", "green")

setup({ repo_prefix = "repo: ", repo_symbol = "*", theme = { repo_color = "cyan" } })
refresh(output('{"icon":"󰊤","owned":true}'))
label("󰊤 repo: *-repo 路径", "cyan") -- Omitted owned color inherits normal color.
setup({ show_remote_icon = false, theme = { repo_color = "cyan", repo_owned_color = "yellow" } })
refresh(output('{"icon":"󰊤","owned":true}'))
label("-repo 路径", "yellow") -- Hiding the icon does not disable ownership styling.
setup()
refresh(output('{"icon":"","owned":false}'))
label(" -repo 路径", "blue")

-- A later navigation invalidates an in-flight metadata result with all Git state.
during_output = function() subscriptions.tab() end
refresh(output('{"icon":"󰊤","owned":true}'))
assert(head.name == nil and head.output == nil and head.repo_info == nil)
during_output = function() cx.active.current.cwd = Url("/elsewhere") end
refresh(output('{"icon":"󰊤","owned":true}'))
assert(head.name == nil and head.output == nil and head.repo_info == nil)
-- TMUX detection is opt-in, sampled once at setup, and independent of themes.
for _, environment in ipairs({ false, "", "/fixture/tmux.sock,123,0" }) do
  for _, enabled in ipairs({ "omitted", false, true }) do
    tmux = environment or nil
    local options = {}
    if enabled ~= "omitted" then options.hide_in_tmux = enabled end
    setup(options)
    local hidden = enabled == true and type(environment) == "string" and environment ~= ""
    assert(head.hidden == hidden)
    if hidden then
      assert(next(subscriptions) == nil and emitted == 0)
      -- Even a direct asynchronous route cannot run git or git-it.
      head:entry({ args = { cwd, "1" } })
      assert(#calls == 0)
      -- A queued result and stale cached data must not restore the header.
      head.request = 1
      save(head, cwd, 1, "leaked", { branch = "main" })
      assert(head.name == nil and head.output == nil)
      head.cwd, head.name, head.output = cwd, "cached", { branch = "main" }
      tmux = nil
      head:recolor({ theme = { repo_color = "red", branch_color = "yellow" } })
      assert(Dotline.coloreds.get.repo_name() == nil)
      assert(Dotline.coloreds.get.githead() == nil)
      assert(next(subscriptions) == nil and #calls == 0 and emitted == 0)
    else
      assert(subscriptions.cd and subscriptions.tab and emitted == 1)
      refresh(nil)
      label("-repo 路径", "blue")
      assert(head.output.branch == "main" and #calls > 0)
    end
  end
end
os.getenv = original_getenv
require = original_require
print("dots: remote metadata, ownership colors, helper fallbacks, render purity and stale-result checks passed")
print("dots: tmux option matrix, hidden jobs/results, setup-only detection and recoloring passed")
