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
other Vim built-ins provide everything needed for the core (file, buf, code and
qfix modes, file operations).

Optional features reach outside Vim, and only when the user invokes them: the
git actions need `git`; the AI add-on needs `bash` and `curl` (it runs
`bin/vproj-ai-chat` and streams over `curl`); `:VprojAgent` needs an agent CLI
(`claude`, `codex`, or `g:vproj_agent_cmd`). Each reports a clear error when its
tool is missing.

**Why:** A project manager loads instantly. Dependencies add startup cost,
version compatibility risk, and installation friction.

## Two Source Files Plus Two Add-ons

`plugin/vproj.vim` (public surface) and `autoload/vproj.vim` (implementation).
Two add-ons are approved, each loaded on demand through its own autoload
namespace: `autoload/vproj/ai.vim` (`vproj#ai#`, AI provider API) and
`autoload/vproj/agent.vim` (`vproj#agent#`, external agent CLI in a terminal,
approved 2026-11-09). They do different jobs and stay separate. Plugin calls
autoload. Never the reverse. No further file without explicit approval.

**Why:** Minimal structural overhead. Vim's autoload mechanism provides lazy
loading — functions in `autoload/` are only loaded when first called. A third
file must justify its existence against the complexity cost of another boundary.

## ASCII-Only Output

All text vproj itself prints is ASCII: pane rows, the status line, messages,
help text and the chat banner. Horizontal rules use `-` or `=`, boxes use
`+ - |`, a branch is `@main`, and a clause break is ` -- `. No Unicode
box-drawing, arrows, dashes or glyphs.

Comments in source may be UTF-8. The rule is line-based so it can be checked: a
source line may hold non-ASCII only if it is a comment-only line, so a code
line with a trailing comment must be ASCII.

User data is not limited. File and directory names pass through unchanged
(CJK and emoji names are supported and tested); only vproj's own text is ASCII.

**Why:** Unicode renders inconsistently across terminals, fonts and locales
(a Vim in a non-UTF-8 locale prints it as garbage). The display must never
depend on a specific terminal emulator, font or locale configuration.

**Enforced by:** `tests/unit/test_ascii_ui.vim`, which scans the source and
fails on any non-ASCII outside a comment-only line.

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

There is no automatic write. Every filesystem write traces to an explicit user
action (for example a file operation, `+`/`-` in code mode, or a confirmed git
command) or to an explicit opt-in setting. Session persistence is the second
kind: the pane saves its state on close only when the user sets
`g:vproj_save_session = 1` (default 0, never write). With the option off,
vproj never creates the session file; it still reads one if it exists.

## Vim9Script Only

All code in Vim9Script (`:def` functions, strict semantics). No legacy
Vimscript (`:function`), no Lua, no Python interop in the core. (The AI add-on runs one bash helper,
`bin/vproj-ai-chat`, in a Vim terminal.)

**Why:** Vim9Script provides type checking, better performance, and strict
semantics. Mixing script versions in one plugin creates subtle compatibility
issues.

## Single Source of Truth

Script-local variables at the top of the autoload file are the workspace. No
state lives outside it. (The add-ons keep only their own per-request state:
streaming job, target buffer, resolved API settings.)
No duplicate copies that can diverge.

**Why:** When there is exactly one place where each piece of state lives,
debugging is a matter of finding what wrote to it. When there are copies, you
spend hours figuring out which one is stale.
