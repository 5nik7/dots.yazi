-- Opaque color references survive option copying and resolve only at setup/refresh.
local M = {}
local paths = setmetatable({}, { __mode = 'k' })
local palette = {
  background='black', foreground='white', muted='darkgray',
  black='black', white='white', red='red', green='green', yellow='yellow',
  blue='blue', magenta='magenta', cyan='cyan', gray='gray',
  error='red', warning='yellow', success='green', accent='blue', info='blue', hint='cyan',
  cursor='white', selection='darkgray', selection_background='darkgray', selection_foreground='white',
  dark_background='black', darker_background='black', lighter_background='black',
  dark_foreground='white', light_foreground='white', bright_foreground='white',
  orange='yellow', brown='darkgray',
}
local ansi = {'black','red','green','yellow','blue','magenta','cyan','white',
  'darkgray','lightred','lightgreen','lightyellow','lightblue','lightmagenta','lightcyan','white'}
for i,name in ipairs(ansi) do palette['color' .. (i-1)] = name end
for _,name in ipairs({'red','green','yellow','blue','magenta','cyan'}) do palette['bright_' .. name] = 'light' .. name end
local git = {
  repo='magenta', repo_owned='yellow', branch='magenta', untracked='magenta',
  modified='yellow', behind='yellow', detached='yellow', missing='yellow',
  staged='green', added='green', clean='green', ahead='green',
  deleted='red', blocked='red', conflict='red', renamed='cyan', copied='cyan', ignored='darkgray',
}
local function reference(path, getter)
  local ref, children = {}, {}
  paths[ref] = path
  return setmetatable(ref, {
    __index = function(_, key)
      assert(type(key)=='string', 'color reference keys must be strings')
      if not children[key] then
        local next_path = {}; for i,v in ipairs(path) do next_path[i]=v end
        next_path[#next_path+1]=key; children[key]=reference(next_path)
      end
      return children[key]
    end,
    __newindex = function() error('color references are read-only') end,
    __call = function() assert(getter, 'only dots.colors is callable'); return getter() end,
    __tostring = function() return 'dots.colors.' .. table.concat(path,'.') end,
  })
end
function M.namespace(getter) return reference({}, getter) end
function M.is(value) return type(value)=='table' and paths[value] ~= nil end
function M.resolve(value, colors)
  local path = assert(paths[value], 'expected color reference')
  local resolved = colors
  for _,key in ipairs(path) do resolved = type(resolved)=='table' and resolved[key] or nil end
  if type(resolved)=='string' then return resolved end
  if #path==1 then resolved=palette[path[1]]
  elseif #path==2 and path[1]=='git' then resolved=git[path[2]] end
  assert(resolved, 'unresolved color reference: ' .. tostring(value))
  return resolved
end
return M
