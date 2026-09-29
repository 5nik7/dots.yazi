local function find_rule(cwd, rules)
  for _, rule in ipairs(rules) do
    if cwd:ends_with(rule.name) then
      return rule
    end
  end
  return {}
end

local function apply_rule(rule)
  ya.emit("sort", {
    rule.sort or "alphabetical",
    reverse = rule.reverse == true,
    dir_first = rule.dir_first ~= false,
  })
end

local function setup(_, rules)
  rules = rules or {}
  ps.sub("cd", function()
    apply_rule(find_rule(cx.active.current.cwd, rules))
  end)
end

return { setup = setup }
