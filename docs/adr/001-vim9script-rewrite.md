# ADR 001: Vim9Script Rewrite from Lua

- **Status**: Accepted
- **Date**: 2026-06-13
- **Author**: Aldous Thoreau

## Context

Vproj (formerly Nam) was originally written in Lua for Neovim, with
compatibility shims for Vim 8.2+. This architecture had several problems:

1. **Dual Runtime Complexity**: The Lua→VimScript bridge (`vim.fn.*`,
   `vim.api.*`) added indirection and made debugging difficult.
2. **Vim 8.2 Lua Limitations**: Vim 8.2's `+lua` support is incomplete
   compared to Neovim's LuaJIT. The compat shims were fragile.
3. **CI Fragility**: Testing on both Lua (Neovim) and VimScript paths
   required maintaining two test frameworks (plenary + vim-spec).
4. **Installation Friction**: Users on Vim 8.2 needed `+lua` compiled in,
   which isn't universal across distributions.

## Decision

Rewrite the entire codebase in pure Vim9Script (`:vim9script`), targeting
Vim 8.2+ as the baseline. Vim9Script provides:

- Strict type annotations (`: bool`, `: string`, `: dict<any>`)
- Native `def` functions with compile-time checking
- No external dependencies required

## Options Considered

### Option A: Pure Vim9Script (Chosen)
- **Pros**: Single runtime, no dependencies, works on all Vim 8.2+
- **Cons**: Vim9Script is Vim-only (not Neovim compatible)

### Option B: Dual Lua + VimScript
- **Pros**: Works on both Vim and Neovim natively
- **Cons**: Two code paths, fragile compat layer, maintenance burden

### Option C: Pure Lua (Neovim-only)
- **Pros**: Modern language, good tooling
- **Cons**: Excludes Vim users, contradicts project goals

## Consequences

- **Positive**: Zero dependencies. Plugin loads on any Vim 8.2+ installation.
- **Positive**: Single test framework (vim-spec), 174 tests, 0 failures.
- **Negative**: Not compatible with Neovim's native Lua runtime.
- **Negative**: Vim9Script has a smaller ecosystem and fewer learning resources.

## References

- `:help vim9script`
- `:help vim9-types`
