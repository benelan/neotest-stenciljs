# neotest-stenciljs

This plugin provides a [StencilJS](https://stenciljs.com) adapter for the
[Neotest](https://github.com/rcarriga/neotest) framework.

## Installation

Using `lazy.nvim`:

```lua
return {
  'nvim-neotest/neotest',
  dependencies = {
    ...,
    'benelan/neotest-stenciljs',
  },
  config = function()
    require('neotest').setup({
      ...,
      adapters = {
        require('neotest-stenciljs')
      }
    })
  end
}
```

Make sure you have the appropriate `treesitter` language parsers installed,
otherwise no tests will be found:

```vim
:TSInstall javascript typescript tsx
```

## Usage

See neotest's documentation for more information on how to run tests.

### Running tests in watch mode

To run test in watch mode, you can either enable it globally in the setup:

```lua
require("neotest").setup({
  ...,
  adapters = {
    require("neotest-stenciljs")({
      stencilTestCommand = require("neotest-stenciljs.stencil-util").getStencilTestCommand(
        vim.fn.expand("%:p:h")
      ) .. " --watchAll",
    }),
  },
})
```

or add a specific keymap to run tests with in mode:

```lua
vim.keymap.set(
  "n",
  "<leader>tw",
  "<cmd>lua require('neotest').run.run({ stencilTestCommand = 'npx stencil test --e2e --spec --no-docs --watchAll ' })<cr>",
  { noremap = true, desc = "Run StencilJS test (watch)" }
)
```

### Parameterized tests

If you want to allow to `neotest-stenciljs` to discover parameterized tests you
need to enable flag `stencil_test_discovery` in config setup:

```lua
require('neotest').setup({
  ...,
  adapters = {
    require('neotest-stenciljs')({
      ...,
      stencil_test_discovery = false,
    }),
  }
})
```

Its also recommended to disable `neotest` `discovery` option like this:

```lua
require("neotest").setup({
  ...,
  discovery = {
    enabled = false,
  },
})
```

## Credits

This was originally copied from [`neotest-jest`](https://github.com/nvim-neotest/neotest-jest).
[StencilJS uses Jest under the hood](https://stenciljs.com/docs/testing-overview),
so most of the code was not changed.
