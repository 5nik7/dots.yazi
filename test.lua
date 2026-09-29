-- Run from this directory: lua test.lua
local calls, modules = {}, {}
local saved_require = require
local setup_order = {}
require = function(name)
  assert(name:sub(1, 1) == ".", "unexpected external dependency: " .. name)
  if not modules[name] then
    modules[name] = {
      setup = function(self, options)
        self.options = options
        setup_order[#setup_order + 1] = name
      end,
      entry = function(self, job) calls[#calls + 1] = { module = self, job = job } end,
      fetch = function(self, job) calls[#calls + 1] = { module = self, job = job }; return true end,
    }
  end
  return modules[name]
end
local notices = {}
ya = { notify = function(notice) notices[#notices + 1] = notice end }
local dots = dofile("main.lua")
local options = { dotline = { padding = { inner = 2 } }, projects = { notify = { title = "Projects" } } }
dots:setup(options)
assert(table.concat(setup_order, ",") == ".ls-colors,.full-border,.git,.folder-rules,.projects,.dotline,.hover,.githead,.hostname-username")
assert(modules[".dotline"].options == options.dotline)
assert(modules[".projects"].options == options.projects)
for _, route in ipairs({ "projects", "githead", "toggle-pane" }) do
  local job = { args = { route, "load", "a project with spaces", force = true }, marker = "keep" }
  dots:entry(job)
  local call = calls[#calls]
  assert(call.module == modules["." .. route])
  assert(call.job.args[1] == "load" and call.job.args[2] == "a project with spaces")
  assert(call.job.args.force == true and call.job.marker == "keep")
  assert(job.args[1] == route and #job.args == 3, "dispatcher mutated its input")
end
local fetch_job = { files = { "fixture" } }
assert(dots:fetch(fetch_job) == true)
assert(calls[#calls].module == modules[".git"] and calls[#calls].job == fetch_job)
local count = #calls
dots:entry({ args = { "unknown" } })
dots:entry({ args = {} })
assert(#calls == count and #notices == 2)
require = saved_require

-- Exercise the actual pane implementation through its sync boundary.
local state, sync_calls = {}, 0
rt = { mgr = { ratio = { 2, 4, 5 } } }
ya = {
  sync = function(fn)
    return function(...)
      sync_calls = sync_calls + 1
      return fn(state, ...)
    end
  end,
  emit = function(event) assert(event == "app:resize") end,
}
local pane = dofile("toggle-pane.lua")
local function toggle(action, expected)
  pane:entry({ args = { action } })
  assert(table.concat(rt.mgr.ratio, ",") == expected)
end
toggle("min-preview", "2,4,0")
toggle("min-preview", "2,4,5")
toggle("max-preview", "2,4,9999")
toggle("max-preview", "2,4,5")
toggle("min-preview", "2,4,0")
rt.mgr.ratio = { 1, 3, 6 }
toggle("max-preview", "1,3,9999")
toggle("max-preview", "1,3,6")
assert(sync_calls == 7)
print("dots: dispatch, setup order, argument preservation, fetch and pane checks passed")

-- Both Git components share one refresh and reject stale results together.
local save, subscriptions, emitted = nil, {}, {}
local urls = {}
Url = function(path)
  if not urls[path] then
    urls[path] = setmetatable({ spec = { is_regular = true } }, { __tostring = function() return path end })
  end
  return urls[path]
end
cx = { active = { current = { cwd = Url("/repo with spaces") } } }
Dotline = { coloreds = { get = {} } }
ui = { render = function() end }
ya = {
  sync = function(fn) save = fn; return fn end,
  quote = function(value) return "'" .. value .. "'" end,
  emit = function(event, args) assert(event == "plugin"); emitted[#emitted + 1] = args end,
}
ps = { sub = function(event, fn) assert(not subscriptions[event]); subscriptions[event] = fn end }
local head = dofile("githead.lua")
head._id = "dots.githead"
head:setup({ repo_prefix = "repo: ", repo_symbol = "*", branch_symbol = "", theme = { repo_color = "cyan" } })
subscriptions.cd()
assert(#emitted == 1 and emitted[1][1] == "dots" and emitted[1][2] == "githead '/repo with spaces' 1")
save(head, "/repo with spaces", 1, "first", { branch = "main" })
assert(Dotline.coloreds.get:repo_name()[1][1] == "repo: *first")
assert(Dotline.coloreds.get:repo_name()[1][2] == "cyan")
assert(Dotline.coloreds.get:githead() ~= nil)
local function head_text()
  local parts = {}
  -- Dotline invokes registered getters as plain functions, without self.
  for _, span in ipairs(Dotline.coloreds.get.githead() or {}) do parts[#parts + 1] = span[1] end
  return table.concat(parts)
end
assert(head_text() == "repo: *first main", head_text())
save(head, "/repo with spaces", 1, "first", {
  branch = "main", unstaged = string.rep("file\n", 169), untracked = string.rep("file\n", 24),
})
assert(head_text() == "repo: *first main !169 ?24", head_text())
assert(Dotline.coloreds.get:githead()[1][2] == "cyan")
save(head, "/repo with spaces", 1, "first", {})
assert(head_text() == "repo: *first", "repository-only output gained trailing whitespace")
subscriptions.tab()
assert(head.name == nil and head.output == nil)
save(head, "/repo with spaces", 1, "stale", { branch = "stale" })
assert(head.name == nil and head.output == nil, "outdated refresh was accepted")
save(head, "/repo with spaces", 2, "latest", { branch = "latest" })
assert(head.name == "latest" and head.output.branch == "latest")
cx.active.current.cwd = Url("/outside")
save(head, "/repo with spaces", 2, "wrong directory", {})
assert(head.name == "latest")
subscriptions.cd()
save(head, "/outside", 3, nil, {})
assert(Dotline.coloreds.get:repo_name() == nil and Dotline.coloreds.get:githead() == nil)
cx.active.current.cwd = Url("/repo with spaces/.git")
subscriptions.cd()
save(head, "/repo with spaces/.git", 4, "repo with spaces", { branch = "main" })
assert(head.name == "repo with spaces" and head.output == nil)
cx.active.current.cwd = Url("remote://fixture")
cx.active.current.cwd.spec.is_regular = false
local before = #emitted
subscriptions.cd()
assert(#emitted == before and head.name == nil and head.output == nil)
print("dots: combined Git refresh, repository styling and stale-result checks passed")
