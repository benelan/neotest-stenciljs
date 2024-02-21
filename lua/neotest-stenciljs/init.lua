---@diagnostic disable: undefined-field
local async = require("neotest.async")
local lib = require("neotest.lib")
local logger = require("neotest.logging")
local util = require("neotest-stenciljs.util")

---@class neotest.StencilOptions
---@field watch? boolean Run test(s) with the `--watchAll` flag
---@field no_build? boolean Run test(s) with the `--no-build` flag
---@field env? table<string, string>|fun(): table<string, string> Set environment variables
---@field cwd? string|fun(): string The current working directory for running tests
---@field filter_dir? fun(name: string, relpath: string, root: string): boolean
---@field is_test_file? fun(file_path: string): boolean

---@class neotest.Adapter
local adapter = { name = "neotest-stenciljs" }

local root_package_json = vim.fn.getcwd() .. "/package.json"

---@param json_content string
---@return boolean
local function has_stencil_dep_in_json(json_content)
  local parsed_json = vim.json.decode(json_content)

  for _, dep_type in ipairs({ "dependencies", "devDependencies" }) do
    if parsed_json[dep_type] then
      for key, _ in pairs(parsed_json[dep_type]) do
        if key == "@stencil/core" then
          return true
        end
      end
    end
  end

  return false
end

---@return boolean
local function has_stencil_dep_in_project_root()
  local success, json_content = pcall(lib.files.read, root_package_json)
  if not success then
    print("cannot read package.json")
    return false
  end

  return has_stencil_dep_in_json(json_content)
end

---@param path string
---@return boolean
local function has_stencil_dep(path)
  local root_path = lib.files.match_root_pattern("package.json")(path)

  if not root_path then
    return false
  end

  local success, json_content = pcall(lib.files.read, root_path .. "/package.json")
  if not success then
    print("cannot read package.json")
    return false
  end

  return has_stencil_dep_in_json(json_content) or has_stencil_dep_in_project_root()
end

---@param file_path string
---@return boolean
local function is_e2e_test_file(file_path)
  return string.match(file_path, "%.e2e%.tsx?$")
end

---@param file_path string
---@return boolean
local function is_spec_test_file(file_path)
  return string.match(file_path, "%.spec%.tsx?$")
end

adapter.root = function(path)
  return lib.files.match_root_pattern("package.json")(path)
end

function adapter.filter_dir(name, relpath, root)
  return not vim.tbl_contains(
    { "node_modules", "dist", "hydrate", "www", ".stencil", ".storybook" },
    name
  )
end

---@param file_path? string
---@return boolean
function adapter.is_test_file(file_path)
  return file_path ~= nil
    and (is_e2e_test_file(file_path) or is_spec_test_file(file_path))
    and has_stencil_dep(file_path)
end

---@async
---@return neotest.Tree | nil
function adapter.discover_positions(path)
  local query = [[
    ; -- Namespaces --
    ; Matches: `describe('context', () => {})`
    ((call_expression
      function: (identifier) @func_name (#eq? @func_name "describe")
      arguments: (arguments (string (string_fragment) @namespace.name) (arrow_function))
    )) @namespace.definition
    ; Matches: `describe('context', function() {})`
    ((call_expression
      function: (identifier) @func_name (#eq? @func_name "describe")
      arguments: (arguments (string (string_fragment) @namespace.name) (function_expression))
    )) @namespace.definition
    ; Matches: `describe.only('context', () => {})`
    ((call_expression
      function: (member_expression
        object: (identifier) @func_name (#any-of? @func_name "describe")
      )
      arguments: (arguments (string (string_fragment) @namespace.name) (arrow_function))
    )) @namespace.definition
    ; Matches: `describe.only('context', function() {})`
    ((call_expression
      function: (member_expression
        object: (identifier) @func_name (#any-of? @func_name "describe")
      )
      arguments: (arguments (string (string_fragment) @namespace.name) (function_expression))
    )) @namespace.definition
    ; Matches: `describe.each(['data'])('context', () => {})`
    ((call_expression
      function: (call_expression
        function: (member_expression
          object: (identifier) @func_name (#any-of? @func_name "describe")
        )
      )
      arguments: (arguments (string (string_fragment) @namespace.name) (arrow_function))
    )) @namespace.definition
    ; Matches: `describe.each(['data'])('context', function() {})`
    ((call_expression
      function: (call_expression
        function: (member_expression
          object: (identifier) @func_name (#any-of? @func_name "describe")
        )
      )
      arguments: (arguments (string (string_fragment) @namespace.name) (function_expression))
    )) @namespace.definition

    ; -- Tests --
    ; Matches: `test('test') / it('test')`
    ((call_expression
      function: (identifier) @func_name (#any-of? @func_name "it" "test")
      arguments: (arguments (string (string_fragment) @test.name) [(arrow_function) (function_expression)])
    )) @test.definition
    ; Matches: `test.only('test') / it.only('test')`
    ((call_expression
      function: (member_expression
        object: (identifier) @func_name (#any-of? @func_name "test" "it")
      )
      arguments: (arguments (string (string_fragment) @test.name) [(arrow_function) (function_expression)])
    )) @test.definition
    ; Matches: `test.each(['data'])('test') / it.each(['data'])('test')`
    ((call_expression
      function: (call_expression
        function: (member_expression
          object: (identifier) @func_name (#any-of? @func_name "it" "test")
          property: (property_identifier) @each_property (#eq? @each_property "each")
        )
      )
      arguments: (arguments (string (string_fragment) @test.name) [(arrow_function) (function_expression)])
    )) @test.definition
  ]]

  return lib.treesitter.parse_positions(path, query, { nested_tests = true })
end

---@param path string
---@return string
local function get_stencil_command(path)
  local git_ancestor = util.find_git_ancestor(path)

  local function find_binary(p)
    local root_path = util.find_node_modules_ancestor(p)
    local stencil_binary = util.path.join(root_path, "node_modules", ".bin", "stencil")

    if util.path.exists(stencil_binary) then
      return stencil_binary
    end

    -- If no binary found and the current directory isn't the parent
    -- git ancestor, let's traverse up the tree again
    if root_path ~= git_ancestor then
      return find_binary(util.path.dirname(root_path))
    end
  end

  local found_binary = find_binary(path)

  if found_binary then
    return found_binary
  end

  return "npx stencil"
end

local function escape_test_pattern(s)
  return (
    s:gsub("%(", "%\\(")
      :gsub("%)", "%\\)")
      :gsub("%]", "%\\]")
      :gsub("%[", "%\\[")
      :gsub("%*", "%\\*")
      :gsub("%+", "%\\+")
      :gsub("%-", "%\\-")
      :gsub("%?", "%\\?")
      :gsub("%$", "%\\$")
      :gsub("%^", "%\\^")
      :gsub("%/", "%\\/")
  )
end

local function get_strategy_config(strategy, command)
  local config = {
    dap = function()
      return {
        name = "Debug Stencil Tests",
        type = "pwa-node",
        request = "launch",
        args = { unpack(command, 2) },
        runtimeExecutable = command[1],
        console = "integratedTerminal",
        internalConsoleOptions = "neverOpen",
      }
    end,
  }
  if config[strategy] then
    return config[strategy]()
  end
end

local function get_env(spec_env)
  return spec_env
end

---@param file_path string
---@return string|nil
local function get_cwd(file_path)
  return nil
end

---@param args neotest.RunArgs
---@return neotest.RunSpec | nil
function adapter.build_spec(args)
  local results_path = async.fn.tempname() .. ".json"
  local tree = args.tree

  if not tree then
    return
  end

  local pos = args.tree:data()
  local test_name_pattern = ".*"

  if pos.type == "test" then
    test_name_pattern = escape_test_pattern(pos.name) .. "$"
  end

  if pos.type == "namespace" then
    test_name_pattern = "^ " .. escape_test_pattern(pos.name)
  end

  local binary = get_stencil_command(pos.path)
  local command = vim.split(binary, "%s+")

  local is_spec = is_spec_test_file(pos.path)
  local is_e2e = is_e2e_test_file(pos.path)

  vim.list_extend(command, {
    "test",
    is_spec and "--spec" or nil,
    is_e2e and "--e2e" or nil,
    not is_spec and not is_e2e and "--spec" or nil,
    not is_spec and not is_e2e and "--e2e" or nil,
    adapter.watch == true and "--watchAll" or nil,
    adapter.no_build == true and "--no-build" or nil,
    "--no-coverage",
    "--testLocationInResults",
    "--verbose",
    "--json",
    "--outputFile=" .. results_path,
    "--testNamePattern=" .. test_name_pattern,
    "--forceExit",
    "--",
    pos.path,
  })

  return {
    command = command,
    cwd = get_cwd(pos.path),
    context = {
      results_path = results_path,
      file = pos.path,
    },
    strategy = get_strategy_config(args.strategy, command),
    env = get_env(args[2] and args[2].env or {}),
  }
end

local function clean_ansi(s)
  return s:gsub("\x1b%[%d+;%d+;%d+;%d+;%d+m", "")
    :gsub("\x1b%[%d+;%d+;%d+;%d+m", "")
    :gsub("\x1b%[%d+;%d+;%d+m", "")
    :gsub("\x1b%[%d+;%d+m", "")
    :gsub("\x1b%[%d+m", "")
end

local function parsed_json_to_results(data, output_file, consoleOut)
  local tests = {}

  for _, testResult in pairs(data.testResults) do
    local testFn = testResult.name

    for _, assertionResult in pairs(testResult.assertionResults) do
      local status, name = assertionResult.status, assertionResult.title

      if name == nil then
        logger.error("Failed to find parsed test result ", assertionResult)
        return {}
      end

      local keyid = testFn

      for _, value in ipairs(assertionResult.ancestorTitles) do
        if value ~= "" then
          keyid = keyid .. "::" .. value
        end
      end

      keyid = keyid .. "::" .. name

      if status == "pending" or status == "todo" then
        status = "skipped"
      end

      tests[keyid] = {
        status = status,
        short = name .. ": " .. status,
        output = consoleOut,
        location = assertionResult.location,
      }

      if not vim.tbl_isempty(assertionResult.failureMessages) then
        local errors = {}

        for i, failMessage in ipairs(assertionResult.failureMessages) do
          local msg = clean_ansi(failMessage)

          errors[i] = {
            line = (assertionResult.location and assertionResult.location.line - 1 or nil),
            column = (assertionResult.location and assertionResult.location.column or nil),
            message = msg,
          }

          tests[keyid].short = tests[keyid].short .. "\n" .. msg
        end

        tests[keyid].errors = errors
      end
    end
  end

  return tests
end

---@async
---@param spec neotest.RunSpec
---@return neotest.Result[]
function adapter.results(spec, b, tree)
  local output_file = spec.context.results_path

  local success, data = pcall(lib.files.read, output_file)

  if not success then
    logger.error("No test output file found ", output_file)
    return {}
  end

  local ok, parsed = pcall(vim.json.decode, data, { luanil = { object = true } })

  if not ok then
    logger.error("Failed to parse test output json ", output_file)
    return {}
  end

  local results = parsed_json_to_results(parsed, output_file, b.output)

  return results
end

local is_callable = function(obj)
  return type(obj) == "function" or (type(obj) == "table" and obj.__call)
end

setmetatable(adapter, {
  ---@param opts neotest.StencilOptions
  __call = function(_, opts)
    if opts.watch ~= nil then
      adapter.watch = opts.watch
    end

    if opts.no_build ~= nil then
      adapter.no_build = opts.no_build
    end

    if is_callable(opts.env) then
      get_env = opts.env ---@diagnostic disable-line: cast-local-type
    elseif opts.env then
      get_env = function(spec_env)
        return vim.tbl_extend("force", opts.env, spec_env) ---@diagnostic disable-line: param-type-mismatch
      end
    end

    if is_callable(opts.cwd) then
      get_cwd = opts.cwd ---@diagnostic disable-line: cast-local-type
    elseif opts.cwd then
      get_cwd = function()
        return opts.cwd
      end
    end

    if is_callable(opts.filter_dir) then
      adapter.filter_dir = opts.filter_dir
    end

    if is_callable(opts.is_test_file) then
      local is_test_file = adapter.is_test_file
      adapter.is_test_file = function(file_path)
        return is_test_file(file_path) and opts.is_test_file(file_path)
      end
    end

    return adapter
  end,
})

return adapter
