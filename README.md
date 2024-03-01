# neotest-stenciljs

This plugin provides a [StencilJS](https://stenciljs.com) adapter for the
[Neotest](https://github.com/rcarriga/neotest) framework.

<!--toc:start-->

- [neotest-stenciljs](#neotest-stenciljs)
  - [Installation](#installation)
  - [Configuration](#configuration)
    - [Stricter file parsing to determine test files](#stricter-file-parsing-to-determine-test-files)
    - [Filter directories searched for tests](#filter-directories-searched-for-tests)
  - [Usage](#usage)
    - [Running tests in watch mode](#running-tests-in-watch-mode)
    - [Running tests without building](#running-tests-without-building)
  - [Known issues](#known-issues)
  - [Credits](#credits)
  - [Disclaimer](#disclaimer)

<!--toc:end-->

## Installation

Install the adapter using your plugin manager, for example with `lazy.nvim`:

```lua
{
  "nvim-neotest/neotest",
  dependencies = {
    "benelan/neotest-stenciljs",
    -- other plugins required by neotest ...
  },
  config = function()
    require("neotest").setup({
      adapters = {
        require("neotest-stenciljs")
        -- other adapters ...
      },
      -- other neotest config options ...
    })
  end
}
```

**IMPORTANT:** Make sure you have the appropriate `treesitter` language parsers
installed, otherwise no tests will be found:

```vim
:TSInstall javascript typescript tsx
```

## Configuration

See the source code for the available configuration options:

https://github.com/benelan/neotest-stenciljs/blob/f98366cee0b767e4779a037a9f1269c4f35bfe69/lua/neotest-stenciljs/init.lua#L7-L13

An example configuration:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-stenciljs")({
      no_build = true,
      env = {
        CI = true,
        PUPPETEER_EXECUTABLE_PATH = "/usr/bin/chromium-browser"
      }
      cwd = function(file_path)
        return vim.fs.dirname(file_path)
      end
    }),
  }
})
```

### Stricter file parsing to determine test files

Use the `is_test_file` option to add a custom criteria for test file discovery.
This is helpful in monorepos where other packages use Jest or Vitest, which use
similar naming patterns.

```lua
---Custom criteria for a file path to determine if it is a stencil test file
---@async
---@param file_path string Path of the potential stencil test file
---@return boolean
is_test_file = function(file_path)
  -- check if the project is "stencil-components" when working in the monorepo
  if
    string.match(file_path, "my-monorepo")
    and not string.match(file_path, "packages/stencil-components")
  then
    return false
  end

  -- this is the default condition
  return string.match(file_path, "%.e2e%.tsx?$")
    or string.match(file_path, "%.spec%.tsx?$")
end,
```

### Filter directories searched for tests

Use the `filter_dir` option to limit the directories to be searched for tests.

```lua
---Filter directories when searching for test files
---@async
---@param name string Name of directory
---@param rel_path string Path to directory, relative to root
---@param root string Root directory of project
---@return boolean
filter_dir = function(name, rel_path, root)
  local full_path = root .. "/" .. rel_path

  if root:match("my-monorepo") then
    return full_path:match("packages/stencil-components/src")
  else
  -- this is the default condition
  return not vim.tbl_contains(
    { "node_modules", "dist", "hydrate", "www", ".stencil", ".storybook" },
    name
  )
  end
end
```

## Usage

See [neotest's documentation](https://github.com/nvim-neotest/neotest#usage) for
information on how to run tests.

### Running tests in watch mode

To always run test(s) with the `--watchAll` flag, you can enable the option
during setup:

```lua
require('neotest').setup({
  adapters = {
    require('neotest-jest')({ watch = true }),
  }
})
```

Alternatively, you can add a specific keymap to run test(s) in watch mode:

```lua
vim.keymap.set(
  "n",
  "<leader>tw",
  "<CMD>lua require('neotest').run.run({ watch = true })<CR>",
  { noremap = true, desc = "Run test (watch)" }
)
```

### Running tests without building

StencilJS provides the `--no-build` flag to run e2e tests without building. You
can enable the flag during setup:

```lua
require('neotest').setup({
  adapters = {
    require('neotest-jest')({ no_build = true }),
  }
})
```

If you used the watch mode keymap method above, make sure to disable the
`--no-build` flag:

```lua
vim.keymap.set(
  "n",
  "<leader>tw",
  "<CMD>lua require('neotest').run.run({ watch = true, no_build = false })<CR>",
  { noremap = true, desc = "Run test (watch)" }
)
```

## Known issues

This adapter currently doesn't work well with Stencil/Jest's
[`it.each`](https://jestjs.io/docs/api#1-testeachtablename-fn-timeout)
syntax, but I hope to fix that in the future. Please log an issue if that's
something you want supported.

The adapter also doesn't work well on tests within `for`/`forEach` loops. Using
the builtin [`it.each`](https://jestjs.io/docs/api#1-testeachtablename-fn-timeout)
or [`describe.each`](https://jestjs.io/docs/api#describeeachtablename-fn-timeout)
syntax should be preferred anyway.

## Credits

This neotest adapter was originally copied from [`neotest-jest`](https://github.com/nvim-neotest/neotest-jest)
and [`neotest-vitest`](https://github.com/marilari88/neotest-vitest). StencilJS
[uses Jest](https://stenciljs.com/docs/testing-overview) under the hood, so a
lot of the code remains unchanged.

## Disclaimer

I am not affiliated, associated, authorized, endorsed by, or in any way
officially connected with StencilJS and Ionic. Any information or opinions
expressed in this project are solely mine and do not necessarily reflect the
views or opinions of StencilJS and Ionic.
