local async = require("nio").tests
local Tree = require("neotest.types").Tree
local plugin = require("neotest-stenciljs")

require("neotest-stenciljs-assertions")
A = function(...)
  print(vim.inspect(...))
end

describe("adapter enabled", function()
  async.it("stenciljs component starter repo", function()
    assert.Not.Nil(plugin.root("./spec"))
  end)

  async.it("disable adapter no package.json", function()
    assert.Nil(plugin.root("."))
  end)
end)

describe("is_test_file", function()
  local original_dir
  before_each(function()
    original_dir = vim.api.nvim_eval("getcwd()")
  end)

  after_each(function()
    vim.api.nvim_set_current_dir(original_dir)
  end)

  async.it("matches comnponent e2e test files", function()
    vim.api.nvim_set_current_dir("./spec")
    assert.is.truthy(plugin.is_test_file("./spec/src/components/my-component/my-component.e2e.ts"))
  end)

  async.it("matches component spec test files", function()
    vim.api.nvim_set_current_dir("./spec")
    assert.is.truthy(plugin.is_test_file("./spec/src/components/my-component/my-component.spec.ts"))
  end)

  async.it("matches util spec test files", function()
    vim.api.nvim_set_current_dir("./spec")
    assert.is.truthy(plugin.is_test_file("./spec/src/utils/util.spec.ts"))
  end)

  async.it("does not match plain ts files", function()
    assert.is.falsy(plugin.is_test_file("./index.ts"))
  end)
end)

describe("discover_positions", function()
  async.it("provides meaningful names from a basic spec", function()
    local positions = plugin.discover_positions("./spec/src/utils/util.spec.ts"):to_list()

    local expected_output = {
      {
        name = "util.spec.ts",
        type = "file",
      },
      {
        {
          name = "format",
          type = "namespace",
        },
        {
          {
            name = "returns empty string for no names defined",
            type = "test",
          },
          {
            name = "formats just first names",
            type = "test",
          },
          {
            name = "formats first and last names",
            type = "test",
          },
          {
            name = "formats first, middle and last names",
            type = "test",
          },
        },
      },
    }

    assert.equals(expected_output[1].name, positions[1].name)
    assert.equals(expected_output[1].type, positions[1].type)
    assert.equals(expected_output[2][1].name, positions[2][1].name)
    assert.equals(expected_output[2][1].type, positions[2][1].type)

    assert.equals(5, #positions[2])
    for i, value in ipairs(expected_output[2][2]) do
      assert.is.truthy(value)
      local position = positions[2][i + 1][1]
      assert.is.truthy(position)
      assert.equals(value.name, position.name)
      assert.equals(value.type, position.type)
    end
  end)
end)

describe("build_spec", function()
  async.it("builds command for file test", function()
    local positions = plugin.discover_positions("./spec/src/utils/util.spec.ts"):to_list()
    local tree = Tree.from_list(positions, function(pos)
      return pos.id
    end)
    local spec = plugin.build_spec({ tree = tree })

    assert.is.truthy(spec)
    local command = spec.command
    assert.is.truthy(command)
    assert.contains(command, "stencil")
    assert.contains(command, "test")
    assert.contains(command, "--spec")
    assert.contains(command, "--testNamePattern=.*")
    assert.contains(command, "./spec/src/utils/util.spec.ts")
    assert.is.truthy(spec.context.file)
    assert.is.truthy(spec.context.results_path)
  end)

  async.it("builds command for namespace", function()
    local positions = plugin.discover_positions("./spec/src/utils/util.spec.ts"):to_list()

    local tree = Tree.from_list(positions, function(pos)
      return pos.id
    end)

    local spec = plugin.build_spec({ tree = tree:children()[1] })

    assert.is.truthy(spec)
    local command = spec.command
    assert.is.truthy(command)
    assert.contains(command, "stencil")
    assert.contains(command, "test")
    assert.contains(command, "--spec")
    assert.contains(command, "--testNamePattern=.*")
    assert.contains(command, "./spec/src/utils/util.spec.ts")
    assert.is.truthy(spec.context.file)
    assert.is.truthy(spec.context.results_path)
  end)
end)
