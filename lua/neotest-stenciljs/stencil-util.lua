local util = require("neotest-stenciljs.util")

local M = {}

function M.is_callable(obj)
  return type(obj) == "function" or (type(obj) == "table" and obj.__call)
end

-- Returns stencil binary from `node_modules` if that binary exists and `npx stencil` otherwise.
---@param path string
---@return string
function M.getStencilTestCommand(path)
  local test_args = "test --e2e --spec --no-docs"
  local gitAncestor = util.find_git_ancestor(path)

  local function findBinary(p)
    local rootPath = util.find_node_modules_ancestor(p)
    local stencilBinary = util.path.join(rootPath, "node_modules", ".bin", "stencil")

    if util.path.exists(stencilBinary) then
      return stencilBinary
    end

    -- If no binary found and the current directory isn't the parent
    -- git ancestor, let's traverse up the tree again
    if rootPath ~= gitAncestor then
      return findBinary(util.path.dirname(rootPath))
    end
  end

  local foundBinary = findBinary(path)

  if foundBinary then
    return foundBinary .. " " .. test_args
  end

  return "npx stencil " .. test_args
end

local stencilConfigPattern = util.root_pattern("stencil.config.ts")

-- Returns stencil config file path if it exists.
---@param path string
---@return string|nil
function M.getStencilConfig(path)
  local rootPath = stencilConfigPattern(path)

  if not rootPath then
    return nil
  end

  local stencilTs = util.path.join(rootPath, "stencil.config.ts")

  if util.path.exists(stencilTs) then
    return stencilTs
  end
end

-- Returns neotest test id from stencil test result.
-- @param testFile string
-- @param assertionResult table
-- @return string
function M.get_test_full_id_from_test_result(testFile, assertionResult)
  local keyid = testFile
  local name = assertionResult.title

  for _, value in ipairs(assertionResult.ancestorTitles) do
    keyid = keyid .. "::" .. value
  end

  keyid = keyid .. "::" .. name

  return keyid
end

return M
