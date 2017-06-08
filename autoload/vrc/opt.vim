"""
" Some functions from ftplugin/rest.vim will be moved here.
"

"""
" Get the default cUrl options defined by g:vrc_curl_opts.
"
" @return dict
"
function! vrc#opt#GetDefaultCurlOpts()
  if !exists('g:vrc_curl_opts')
    return {}
  endif
  let opts = eval('g:vrc_curl_opts')
  if type(opts) != type({})
    echoerr 'Option vrc_curl_opts should be a dictionary.'
    return {}
  endif
  return copy(opts)
endfunction

"""
" Convert a dictionary of cUrl options to list.
"
" @param  dict a:dictOpts {'opt1': 'x', 'opt2': ['y', 'z']}
" @return list ['opt', 'x', 'opt2', 'y', 'opt2', 'z']
"
function! vrc#opt#DictToCurlArgs(dictOpts)
  let opts = []
  for [key, optVal] in items(a:dictOpts)
    if empty(optVal)
      call add(opts, key)
      continue
    endif

    " Convert optVal to list.
    if type(optVal) != type([])
      let optVal = [optVal]
    endif
    for val in optVal
      call add(opts, key)
      call add(opts, val)
    endfor
  endfor
  return opts
endfunction

"""
" Check if a dict has one of the given keys.
"
" @param  dict     a:dictOpts
" @param  string[] a:keys
" @return boolean
"
function! vrc#opt#DictHasKeys(dictOpts, keys)
  for kk in a:keys
    if has_key(a:dictOpts, kk)
      return 1
    endif
  endfor
  return 0
endfunction
