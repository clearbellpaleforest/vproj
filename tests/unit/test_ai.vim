vim9script

# Test suite for vproj AI module (autoload/vproj/ai.vim)
# Run: vim -N -u NONE -S tests/unit/test_ai.vim -c 'qall!'

var failures: number = 0
g:failures = 0

def Assert(cond: bool, msg: string): void
  if cond
    echom 'PASS: ' .. msg
  else
    echom 'FAIL: ' .. msg
    g:failures += 1
  endif
enddef

# Load vproj first (ai.vim depends on vproj functions)
execute 'source' expand('<sfile>:p:h:h:h') .. '/src/autoload/vproj.vim'
execute 'source' expand('<sfile>:p:h:h:h') .. '/src/autoload/vproj/ai.vim'

echom '=== test_ai.vim ==='

# ── JsonEscape ──
# JsonEscape wraps in quotes and escapes special chars
var je_plain: string = vproj#ai#JsonEscape('hello')
Assert(je_plain =~ '^".*"$', 'JsonEscape: wraps in quotes')
Assert(stridx(je_plain, 'hello') > 0, 'JsonEscape: contains input')

var je_quote: string = vproj#ai#JsonEscape('he"llo')
Assert(stridx(je_quote, '\"') > 0, 'JsonEscape: escapes double quote')

var je_bs: string = vproj#ai#JsonEscape('he\llo')
Assert(stridx(je_bs, '\\') > 0, 'JsonEscape: escapes backslash')

var je_nl: string = vproj#ai#JsonEscape("line1\nline2")
Assert(stridx(je_nl, '\n') > 0, 'JsonEscape: escapes newline')

var je_tab: string = vproj#ai#JsonEscape("tab\there")
Assert(stridx(je_tab, '\t') > 0, 'JsonEscape: escapes tab')

var je_empty: string = vproj#ai#JsonEscape('')
Assert(je_empty == '""', 'JsonEscape: empty string → ""')

# ── ExtractJsonField ──
Assert(vproj#ai#ExtractJsonField('{"key":"value"}', 'key') == 'value', 'ExtractJsonField: simple field')
Assert(vproj#ai#ExtractJsonField('{"key": "value"}', 'key') == 'value', 'ExtractJsonField: spaced field')
Assert(vproj#ai#ExtractJsonField('{"a":1,"b":2}', 'b') == '2', 'ExtractJsonField: second field')
Assert(vproj#ai#ExtractJsonField('{"deep":{"nested":"x"}}', 'deep') == '{"nested":"x"}', 'ExtractJsonField: nested object')
Assert(vproj#ai#ExtractJsonField('{"key":"value"}', 'missing') == '', 'ExtractJsonField: missing field')
Assert(vproj#ai#ExtractJsonField('not json', 'key') == '', 'ExtractJsonField: non-JSON')
Assert(vproj#ai#ExtractJsonField('', 'key') == '', 'ExtractJsonField: empty input')

# ── ExtractCodeBlocks ──
var single: list<dict<any>> = vproj#ai#ExtractCodeBlocks("```vim\necho 'hi'\n```")
Assert(len(single) == 1, 'ExtractCodeBlocks: single block count')
Assert(get(single[0], 'language', '') == 'vim', 'ExtractCodeBlocks: language tag')
Assert(get(single[0], 'code', '') == "echo 'hi'", 'ExtractCodeBlocks: code content')

var multi: list<dict<any>> = vproj#ai#ExtractCodeBlocks("```python\nx=1\n```\n```vim\necho 'y'\n```")
Assert(len(multi) == 2, 'ExtractCodeBlocks: multi block count')
Assert(get(multi[1], 'language', '') == 'vim', 'ExtractCodeBlocks: second language')

var no_fences: list<dict<any>> = vproj#ai#ExtractCodeBlocks("just some text\nno code here")
Assert(len(no_fences) == 0, 'ExtractCodeBlocks: no fences returns empty')

var empty_block: list<dict<any>> = vproj#ai#ExtractCodeBlocks("```\n\n```")
Assert(len(empty_block) == 0, 'ExtractCodeBlocks: empty fence block')

var no_lang: list<dict<any>> = vproj#ai#ExtractCodeBlocks("```\ncode\n```")
Assert(len(no_lang) == 1, 'ExtractCodeBlocks: no lang tag')
Assert(get(no_lang[0], 'code', '') == 'code', 'ExtractCodeBlocks: code without lang')

# ── Function existence checks ──
# Core exports
Assert(exists('*vproj#ai#AiTerminalChat'), 'Export: AiTerminalChat')
Assert(exists('*vproj#ai#AiCall'), 'Export: AiCall')
Assert(exists('*vproj#ai#AiPrompt'), 'Export: AiPrompt')
Assert(exists('*vproj#ai#AiPromptFromKey'), 'Export: AiPromptFromKey')
Assert(exists('*vproj#ai#StreamCancelCmd'), 'Export: StreamCancelCmd')
# Newly exported for testing
Assert(exists('*vproj#ai#JsonEscape'), 'Export: JsonEscape')
Assert(exists('*vproj#ai#ExtractJsonField'), 'Export: ExtractJsonField')
Assert(exists('*vproj#ai#BuildRequestBody'), 'Export: BuildRequestBody')
Assert(exists('*vproj#ai#ExtractCodeBlocks'), 'Export: ExtractCodeBlocks')
Assert(exists('*vproj#ai#AiConfigure'), 'Export: AiConfigure')
Assert(exists('*vproj#ai#AiCallStream'), 'Export: AiCallStream')

# ── Cleanup and report ──
echom '---'
echom 'AI module tests: ' .. (g:failures == 0 ? 'ALL PASSED' : g:failures .. ' FAILURES')
if g:failures > 0
  cquit!
endif
