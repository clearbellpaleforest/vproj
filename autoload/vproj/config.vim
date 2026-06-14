vim9script

# DeepMerge recursively merges two dicts and returns a new dict.
# The override dict takes precedence over the base dict.
def DeepMerge(base: dict<any>, override: dict<any>): dict<any>
  var result: dict<any> = deepcopy(base)
  for [key, val] in items(override)
    if type(val) == v:t_dict && type(result->get(key)) == v:t_dict
      result[key] = DeepMerge(result[key], val)
    else
      result[key] = val
    endif
  endfor
  return result
enddef

# Setup merges user_opts over the default configuration and returns the result.
export def Setup(user_opts: dict<any>): dict<any>
  var defaults: dict<any> = {
    hotkey: '<F2>',
    width: 45,
    auto_open: false,
    labels: {
      tiers: ['1234567890', 'asdfghjkl', 'qwertyuiop', 'zxcvbnm'],
      overflow_style: 'double',
    },
    modes: {
      buffers: {enabled: true},
      files: {enabled: true},
      symbols: {enabled: true},
      git: {enabled: true},
      outline: {enabled: true},
    },
    workspace: {
      auto_save: true,
      auto_restore: true,
      path: expand('~/.local/share/vproj/workspaces/'),
    },
    cache: {
      project_ttl: 30,
      git_ttl: 5,
      lsp_ttl: 10,
    },
  }
  return DeepMerge(defaults, user_opts)
enddef
