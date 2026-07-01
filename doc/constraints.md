# Constraints

Hard boundaries the system must never violate. These are not features. They are
walls.

## Cross-Platform

Must run on Linux and macOS without platform-specific code paths. Vim provides
the compatibility layer; we don't add our own.

**Why:** The user's machine may be either. The project manager must not be the
reason a configuration doesn't port.

## No External Dependencies

Zero dependencies beyond Vim itself. No Python modules, no Lua libraries, no
shell utilities beyond POSIX. `readdir()`, `getbufinfo()`, `readblob()`, and
other Vim built-ins provide everything needed.

**Why:** A project manager loads instantly. Dependencies add startup cost,
version compatibility risk, and installation friction.

## Two Source Files

`plugin/vproj.vim` (public surface) and `autoload/vproj.vim` (implementation).
Plugin calls autoload. Never the reverse. No third file without explicit
approval.

**Why:** Minimal structural overhead. Vim's autoload mechanism provides lazy
loading — functions in `autoload/` are only loaded when first called. A third
file must justify its existence against the complexity cost of another boundary.

## ASCII-Only Separators

No Unicode box-drawing characters. Dashes only for horizontal rules.

**Why:** Unicode box-drawing renders inconsistently across terminals and fonts.
The display must never depend on a specific terminal emulator or font
configuration.

## Explicit Imperative Flow

Commands change state then call `Render()`. Functions call functions directly.
No dispatchers, no registries, no callback chains whose destination you can't
find with grep.

**Why:** A reader must be able to read the code top to bottom and see who calls
whom. Implicit control flow is the leading cause of "it works but I don't know
why" bugs in plugin code.

## Filesystem Writes Gated by User Action

Every `writefile()`, `delete()`, `rename()`, `mkdir()` call must trace back to
an explicit user action. No automatic file creation. No surprise writes.

**Why:** A mistake with filesystem calls can damage the user's machine.
Automated writes are the most dangerous kind.

## Vim9Script Only

All code in Vim9Script (`:def` functions, strict semantics). No legacy
Vimscript (`:function`), no Lua, no Python interop in the core.

**Why:** Vim9Script provides type checking, better performance, and strict
semantics. Mixing script versions in one plugin creates subtle compatibility
issues.

## Single Source of Truth

Script-local variables at the top of the autoload file are the workspace. No
state lives outside it. No duplicate copies that can diverge.

**Why:** When there is exactly one place where each piece of state lives,
debugging is a matter of finding what wrote to it. When there are copies, you
spend hours figuring out which one is stale.
