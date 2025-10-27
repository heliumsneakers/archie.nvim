# Archie.nvim

Archie is a lightweight Neovim assistant that pipes your editing context to the Codex CLI (model `gpt-5`) and streams the result back as inline ghost text or ad-hoc prompts. It is designed for contributors who already have Codex access bundled with their OpenAI login—no additional OpenAI API billing is required.

## Requirements
- Neovim 0.9 or newer with Lua plugins enabled
- [`codex`](https://github.com/openai/codex) CLI installed and authenticated (`codex login`)
- [`nvim-lua/plenary.nvim`](https://github.com/nvim-lua/plenary.nvim) available in your runtimepath

## Installation (Lazy.nvim)
```lua
{
  "heliumsneakers/archie.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("archie").setup({
      codex = {
        model = "gpt-5",
        -- cmd = "codex",      -- override if codex lives elsewhere
        -- args = { "--json" } -- forward extra CLI flags if needed
      },
      enable_autocomplete = true,
      autocomplete_delay = 250,
    })
  end,
}
```

## Using Archie
- Run `codex login` before launching Neovim so the CLI can reach your Codex account.
- Enter insert mode and start typing—Archie requests a completion after brief pauses and renders it as inline ghost text. Press `<S-Tab>` to accept the suggestion.
- Hit `<Space>|` in normal mode to open the Archie menu. Option 1 opens a prompt window that sends a free-form request to Codex, inserting the answer at the cursor when it returns.
- Toggle autocomplete from the menu if you want to suspend ghost suggestions temporarily.

### Tips
- Archie captures roughly ten lines of code around the cursor plus the current line prefix/suffix to ground completions. Keep an eye on overly long files; trimming whitespace or comments near the cursor often improves results.
- You can pass additional Codex CLI flags via `codex.args` if your environment requires a proxy or specific profile.
- Errors (e.g., missing login, network hiccups) surface through `vim.notify`; they won’t insert text or leave stale ghost hints.

Enjoy the inline Codex experience—file issues or PRs if you hit edge cases. 
