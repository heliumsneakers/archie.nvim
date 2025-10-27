# Repository Guidelines

## Project Structure & Module Organization
Runtime code lives under `lua/archie/`. `init.lua` wires up `setup()` and menu keymaps. `api.lua` now shells out to the Codex CLI, handling prompts, temp files, and error surfacing. `completion.lua` owns ghost-text state and calls `api.request_inline_completion()`; it uses `lsp_bridge.lua` for cursor-aware context (prefix, suffix, nearby lines). `ui.lua` keeps the command palette for ad-hoc Codex queries. Keep new modules under `lua/archie/` and require them from `init.lua` so Neovim can load them via `require('archie.*')`.

## Build, Test, and Development Commands
- `stylua lua` — format Lua sources before committing. Install `stylua` locally or via Mason.
- `codex login` — confirm the user session before exercising completions.
- `nvim --clean -u NONE "+lua require('archie').setup({ codex = { model = 'gpt-5' } })"` — smoke-test the plugin in a minimal session; trigger completions with `<S-Tab>` after a few keystrokes.
- `:luafile %` — reload the current buffer while iterating on a module.

## Coding Style & Naming Conventions
Use two-space indentation, `snake_case` identifiers, and module tables (`local M = {}`) for exports. Keep helper functions near call sites, surface errors with `vim.notify`, and schedule UI updates via `vim.schedule` when coming off async jobs. External dependencies are `plenary.job`, the Codex CLI (`codex` binary), and Neovim’s Lua API. Avoid hard-coding credentials; rely on the user’s Codex login.

## Testing Guidelines
There is no automated suite yet. Manual flow: ensure `codex login` succeeds, start Neovim with Archie, type in insert mode to trigger inline ghost text, accept it with `<S-Tab>`, and confirm the completion inserts at the cursor. For robustness, simulate Codex failures by disconnecting network or running with an invalid model name and verify that `vim.notify` surfaces actionable errors without leaving stale ghost text.

## Commit & Pull Request Guidelines
Follow the existing history: concise, present-tense subjects (“ui changes”, “returned toggle_ghost”). Keep changes focused; squash-on-merge is common. Pull requests should describe intent, list manual validation steps, call out Codex model assumptions (`gpt-5`, custom args), and include screenshots or recordings when UI behavior shifts. Link issues or discussions when relevant.

## Configuration Notes
`require('archie').setup({ codex = { cmd = 'codex', model = 'gpt-5', codex_args = {...} } })` lets users override the Codex binary, model, or extra CLI args. Respect environment variables (e.g. `OPENAI_API_KEY`) and never persist tokens. Document any new CLI requirements or feature flags in README updates before merging.
