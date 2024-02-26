local lib = require("neotest.lib")
local M = {}

-- Returns neotest test id from test result.
-- @param testFile string
-- @param assertionResult table
-- @return string
function M.get_test_full_id_from_test_result(test_file, assertion_result)
  local keyid = test_file
  local name = assertion_result.title

  for _, value in ipairs(assertion_result.ancestorTitles) do
    keyid = keyid .. "::" .. value
  end

  keyid = keyid .. "::" .. name

  return keyid
end

-- Traverses through whole Tree and returns all parameterized tests positions.
-- All parameterized test positions should have `is_parameterized` property on it.
-- @param positions neotest.Tree
-- @return neotest.Tree[]
function M.get_parameterized_tests_positions(positions)
  local parameterized_tests_positions = {}

  for _, value in positions:iter_nodes() do
    local data = value:data()

    if data.type == "test" and data.is_parameterized == true then
      parameterized_tests_positions[#parameterized_tests_positions + 1] = value
    end
  end

  return parameterized_tests_positions
end

-- Synchronously runs `stencil test` in `file_path` directory skipping all tests and returns output.
-- Output have all of the test names inside it. It skips all tests by adding
-- extra `--testPathPattern` parameter to test command with placeholder string that should never exist.
-- @param file_path string - path to file to search for tests
-- @return table - parsed test results
local function run_test_discovery(file_path)
  local command = {
    "npx",
    "stencil",
    "test",
    "--spec",
    "--e2e",
    "--no-build",
    "--no-coverage",
    "--testLocationInResults",
    "--verbose",
    "--json",
    "-t",
    "@______________PLACEHOLDER______________@",
    "--",
    file_path,
  }

  local result = { lib.process.run(command, { stdout = true }) }

  if not result[2] then
    return nil
  end

  local json_string = result[2].stdout

  if not json_string or #json_string == 0 then
    return nil
  end

  return vim.json.decode(json_string, { luanil = { object = true } })
end

-- Searches through whole test command output and returns array of all tests at given `position`.
-- @param test_output table
-- @param position number[]
-- @return { keyid: string, name: string }[]
local function get_tests_ids_at_position(test_output, position)
  local test_ids_at_position = {}
  for _, test_result in pairs(test_output.testResults) do
    local test_file = test_result.name

    for _, assertion_result in pairs(test_result.assertionResults) do
      local location, name = assertion_result.location, assertion_result.title

      if position[1] <= location.line - 1 and position[3] >= location.line - 1 then
        local keyid = M.get_test_full_id_from_test_result(test_file, assertion_result)

        test_ids_at_position[#test_ids_at_position + 1] = { keyid = keyid, name = name }
      end
    end
  end

  return test_ids_at_position
end

-- First runs tests in `file_path` to get all of the tests in the file. Then it takes all of
-- the parameterized tests and finds tests that were in the same position as parameterized test
-- and adds new tests (with range=nil) to the parameterized test.
-- @param file_path string
-- @param each_tests_positions neotest.Tree[]
function M.enrich_positions_with_parameterized_tests(
  file_path,
  parsed_parameterized_tests_positions
)
  local test_discovery_output = run_test_discovery(file_path)

  if test_discovery_output == nil then
    return
  end

  for _, value in pairs(parsed_parameterized_tests_positions) do
    local data = value:data()

    local parameterized_test_results_for_position =
      get_tests_ids_at_position(test_discovery_output, data.range)

    for _, test_result in ipairs(parameterized_test_results_for_position) do
      local new_data = {
        id = test_result.keyid,
        name = test_result.name,
        path = data.path,
      }
      new_data.range = nil

      local new_pos = value:new(new_data, {}, value._key, {}, {})
      value:add_child(new_data.id, new_pos)
    end
  end
end

-- Replaces all of the jest parameters (named and unnamed) with `.*` regex pattern.
-- It allows to run all of the parameterized tests in a single run. Idea inspired by Webstorm jest plugin.
-- @param test_name string - test name with escaped characters
-- @returns string
function M.replace_test_parameters_with_regex(test_name)
  -- https://jestjs.io/docs/api#1-testeachtablename-fn-timeout
  local parameter_types = {
    "%%p",
    "%%s",
    "%%d",
    "%%i",
    "%%f",
    "%%j",
    "%%o",
    "%%#",
    "%%%%",
  }

  -- replace named parameters: named characters can be single word (like $parameterName)
  -- or field access words (like $parameterName.fieldName)
  local result = test_name:gsub("\\$[%a%.]+", ".*")

  for _, parameter in ipairs(parameter_types) do
    result = result:gsub(parameter, ".*")
  end

  return result
end

return M
