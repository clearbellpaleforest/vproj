vim9script

# Default single-character label tiers.
# Four rows of home-row-adjacent keys: 36 direct single-char labels.
export const DefaultTiers: list<string> = [
    '1234567890',
    'asdfghjkl',
    'qwertyuiop',
    'zxcvbnm',
]

# Generate(count, tiers?, overflow_style?) Returns a list of label strings up
# to `count` entries.
#
#   tiers:          list<string> — default DefaultTiers
#   overflow_style: 'double' (default) — unrecognized values skip overflow
#
# Single-char labels are drawn from all tiers in order (36 max with defaults).
# Beyond 36 items, if overflow_style is 'double', two-char labels are
# generated (aa, ab, ac, ..., ba, bb, ...).
# When count exceeds available label combinations, the result is shorter than
# count. Callers must check the result length.
# Called via vproj#labels#Generate() (Vim autoload resolves the path).
export def Generate(
    count: number,
    tiers: list<string> = DefaultTiers,
    overflow_style: string = 'double'
): list<string>
    var labels: list<string> = []
    var flat_chars: list<string> = []

    # Flatten the tier strings into individual characters
    for tier in tiers
        for ch in tier->split('\zs')
            add(flat_chars, ch)
        endfor
    endfor

    if empty(flat_chars)
        return labels
    endif

    # Tier 1: single-character labels
    var idx: number = 0
    for ch in flat_chars
        if idx >= count
            break
        endif
        add(labels, ch)
        idx += 1
    endfor

    # Tier 2: double-character labels for overflow
    if idx < count && overflow_style == 'double'
        for c1 in flat_chars
            if idx >= count
                break
            endif
            for c2 in flat_chars
                if idx >= count
                    break
                endif
                add(labels, c1 .. c2)
                idx += 1
            endfor
        endfor
    endif

    return labels
enddef

# BuildMap(items, label_cfg?) Returns {label_map: dict, lines: list<string>}.
#
#   items:     list<dict<any>> — each item must have at least a 'name' key
#   label_cfg: dict<any> with optional keys:
#                'tiers'          — list<string> (default DefaultTiers)
#                'overflow_style' — string (default 'double')
#
# The returned label_map maps each label string to its item.
# The returned lines are formatted as "label name" strings.
# Called via vproj#labels#BuildMap() (Vim autoload resolves the path).
export def BuildMap(
    items: list<dict<any>>,
    label_cfg: dict<any> = {}
): dict<any>
    var count: number = len(items)
    var tiers: list<string> = get(label_cfg, 'tiers', DefaultTiers)
    var overflow_style: string = get(label_cfg, 'overflow_style', 'double')
    var lbls: list<string> = Generate(count, tiers, overflow_style)
    var label_map: dict<any> = {}
    var lines: list<string> = []

    # Guard against Generate returning fewer labels than items (empty tiers,
    # unrecognized overflow_style, or label space exhaustion).
    if len(lbls) < count
        count = len(lbls)
    endif

    for idx in range(count)
        var label: string = lbls[idx]
        var item: dict<any> = items[idx]
        label_map[label] = item
        add(lines, label .. ' ' .. get(item, 'name', ''))
    endfor

    return {label_map: label_map, lines: lines}
enddef
