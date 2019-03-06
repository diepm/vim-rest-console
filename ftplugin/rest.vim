setlocal commentstring=#%s

let s:vrc_auto_format_response_patterns = {
  \ 'json': 'python -m json.tool',
  \ 'xml': 'xmllint --format -',
\}

let s:vrc_glob_delim      = '\v^--\s*$'
let s:vrc_comment_delim   = '\c\v^\s*(#|//)'
let s:vrc_block_delimiter = '\c\v^\s*HTTPS?://|^--\s*$'

let s:deprecatedMessages = []
let s:deprecatedCurlOpts = {
  \ 'vrc_connect_timeout': '--connect-timeout',
  \ 'vrc_cookie_jar': '-b and -c',
  \ 'vrc_follow_redirects': '-L',
  \ 'vrc_include_response_header': '-i',
  \ 'vrc_max_time': '--max-time',
  \ 'vrc_resolve_to_ipv4': '--ipv4',
  \ 'vrc_ssl_secure': '-k',
\}

"""
" Properly escape string to use in Windows and Non-Windows shells
"
" @param  string val
" @return string
"
function! s:Shellescape(val)
  if has("win32")
    return '"'.substitute(a:val, '["&\\]', '\\&', 'g').'"'
  else
    return shellescape(a:val)
  endif
endfunction

"""
" Trim both ends of a string.
"
" @param  string txt
" @return string
"
function! s:StrTrim(txt)
  return substitute(a:txt, '\v^\s*(\S(.*\S)*)\s*$', '\1', 'g')
endfunction

"""
" Get a VRC option. Use the given default value if option not found.
"
" @param  string a:opt
" @param  mixed  a:defVal
" @return mixed
"
function! s:GetOpt(opt, defVal)
  " Warn if a:opt is deprecated.
  let curlOpt = get(s:deprecatedCurlOpts, a:opt, '')

  if exists('b:' . a:opt)
    if !empty(curlOpt)
      call s:DeprecateOpt(a:opt, curlOpt)
    endif
    return eval('b:' . a:opt)
  endif
  if exists('g:' . a:opt)
    if !empty(curlOpt)
      call s:DeprecateOpt(a:opt, curlOpt)
    endif
    return eval('g:' . a:opt)
  endif
  return a:defVal
endfunction

"""
" Handle a deprecated option.
"
" @param string a:opt
" @param string a:forOpt
"
function! s:DeprecateOpt(opt, forOpt)
  let msg = 'Option `' . a:opt . '` is deprecated and will be removed. '
        \ . 'Use the cUrl option(s) ' . a:forOpt . ' instead.'

  echohl WarningMsg | echom msg | echohl None
  call add(s:deprecatedMessages, msg)
endfunction

"""
" Get a value from a VRC dictionary option.
"
" @param  dict   a:dictName
" @param  string a:key
" @param  mixed  a:defVal
" @return mixed
"
function! s:GetDict(dictName, key, defVal)
  for prefix in ['b', 'g', 's']
    let varName = prefix . ':' . a:dictName
    if exists(varName) && has_key(eval(varName), a:key)
      return get(eval(varName), a:key)
    endif
  endfor
  return a:defVal
endfunction


"""
" Get the first and last line numbers of the
" request block enclosing the cursor.
"
" @return list [int, int]
"
function! s:LineNumsRequestBlock()
  let curPos = getpos('.')

  let blockStart = 0
  let blockEnd   = 0
  let lineNumGlobDelim = s:LineNumGlobSectionDelim()

  """ Find the start of the enclosing request block.
  normal! $
  let blockStart = search(s:vrc_block_delimiter, 'bn')
  if !blockStart || blockStart > curPos[1] || blockStart <= lineNumGlobDelim
    call cursor(curPos[1:])
    return [0, 0]
  endif

  """ Find the start of the next request block.
  let blockEnd = search(s:vrc_block_delimiter, 'n') - 1
  if blockEnd <= blockStart
    let blockEnd = line('$')
  endif
  call cursor(curPos[1:])
  return [blockStart, blockEnd]
endfunction

"""
" @return int The line number of the global section delimiter.
"
function! s:LineNumGlobSectionDelim()
  let curPos = getpos('.')
  normal! gg
  let lineNum = search(s:vrc_glob_delim, 'cn')
  call cursor(curPos[1:])
  return lineNum
endfunction

"""
" Parse host between the given line numbers (inclusive end).
"
" @param  int  a:start
" @param  int  a:end
" @return list [line num or 0, string]
"
function! s:ParseHost(start, end)
  if a:end < a:start
    return [0, '']
  endif
  let curPos = getpos('.')
  call cursor(a:start, 1)
  let lineNum = search('\v\c^\s*HTTPS?://', 'cn', a:end)
  call cursor(curPos[1:])
  if !lineNum
    return [lineNum, '']
  endif
  return [lineNum, s:StrTrim(getline(lineNum))]
endfunction

"""
" Parse the query.
"
" @return list [line num or 0, string]
"
function! s:ParseVerbQuery(start, end)
  let curPos = getpos('.')
  call cursor(a:start, 1)
  let lineNum = search(
    \ '\c\v^(GET|POST|PUT|DELETE|HEAD|PATCH|OPTIONS|TRACE)\s+',
    \ 'cn',
    \ a:end
  \)
  call cursor(curPos[1:])
  if !lineNum
    return [lineNum, '']
  endif
  return [lineNum, s:StrTrim(getline(lineNum))]
endfunction

"""
" Parse header options between the given line numbers (inclusive end).
"
" @param  int  a:start
" @param  int  a:end
" @return dict {'header1': 'value1', 'header2': 'value2'}
"
function! s:ParseHeaders(start, end)
  let contentTypeOpt = s:GetOpt('vrc_header_content_type', 'application/json')
  let headers = {'Content-Type': contentTypeOpt}
  if (a:end < a:start)
    return headers
  endif

  let lineBuf = getline(a:start, a:end)
  let hasContentType = 0
  for line in lineBuf
    let line = s:StrTrim(line)
    if line ==? '' || line =~? s:vrc_comment_delim || line =~? '\v^--?\w+'
      continue
    endif
    let sepIdx = stridx(line, ':')
    if sepIdx > -1
      let key = s:StrTrim(line[0:sepIdx - 1])
      let headers[key] = s:StrTrim(line[sepIdx + 1:])
    endif
  endfor
  return headers
endfunction

"""
" Parse values in global section.
"
" @param  int  a:start
" @param  int  a:end
" @return dict {'var1': 'value1', 'var2': 'value2'}
"
function! s:ParseVals(start, end)
  let vals = {}
  if (a:end < a:start)
    return vals
  endif

  let lineBuf = getline(a:start, a:end)

  for line in lineBuf
    let line = s:StrTrim(line)
    if line ==? '' || line =~? s:vrc_comment_delim
      continue
    endif
    let sepIdx = stridx(line, '=')
    if sepIdx > -1
      let key = s:StrTrim(line[0:sepIdx - 1])
      let val = s:StrTrim(line[sepIdx + 1:])
      if val[:0] is# "$"
        let vals[key] = expand(val)
      else
        let vals[key] = val
      endif
    endif
  endfor
  return vals
endfunction

"""
" Parse the global section.
"
" @return dict { 'host': string, 'headers': {}, 'curlOpts': {}, vals': {} }
"
function! s:ParseGlobSection()
  let globSection = {
    \ 'host': '',
    \ 'headers': {},
    \ 'curlOpts': {},
    \ 'vals': {},
  \}

  """ Search for the line of the global section delimiter.
  let lastLine = s:LineNumGlobSectionDelim()
  if !lastLine
    return globSection
  endif

  """ Parse global host.
  let [hostLine, host] = s:ParseHost(1, lastLine - 1)

  """ Parse global headers.
  let headers = s:ParseHeaders(hostLine + 1, lastLine - 1)

  """ Parse curl options.
  let curlOpts = s:ParseCurlOpts(hostLine + 1, lastLine - 1)

  """ Parse global vals.
  let vals = s:ParseVals(hostLine + 1, lastLine - 1)

  let globSection = {
    \ 'host': host,
    \ 'headers': headers,
    \ 'curlOpts': curlOpts,
    \ 'vals': vals,
  \}
  return globSection
endfunction

"""
" Parse the specified cUrl options.
"
" @param  int  a:fromLine
" @param  int  a:toLine
" @return dict Dict of lists {'-a': [x, y], '-b': [z], '--opt': []}
"
function! s:ParseCurlOpts(fromLine, toLine)
  let curlOpts = {}
  for line in getline(a:fromLine, a:toLine)
    let line = s:StrTrim(line)
    if line !~? '\v^--?\w+'
      continue
    endif
    let [copt; vals] = split(line, '\v\s', 0)
    if !has_key(curlOpts, copt)
      let curlOpts[copt] = []
    endif
    if !empty(vals)
      call add(curlOpts[copt], join(vals, ' '))
    endif
  endfor
  return curlOpts
endfunction

"""
" Parse the request block.
"
" @param  int  a:start
" @param  int  a:resumeFrom (inclusive)
" @param  int  a:end (inclusive)
" @param  dict a:globSection
" @return dict {
"                'success':     boolean,
"                'resumeFrom':  int,
"                'msg':         string,
"                'host':        string,
"                'headers':     dict,
"                'curlOpts':    dict,
"                'httpVerb':    string,
"                'requestPath': string,
"                'dataBody':    string,
"              }
"
function! s:ParseRequest(start, resumeFrom, end, globSection)
  """ Parse host.
  let [lineNumHost, host] = s:ParseHost(a:start, a:end)
  if !lineNumHost
    let host = get(a:globSection, 'host', '')
    let lineNumHost = a:start
  endif
  if empty(host)
    return {
      \ 'success': 0,
      \ 'msg': 'Missing host',
    \}
  endif

  """ Parse the HTTP verb query.
  let [lineNumVerb, restQuery] = s:ParseVerbQuery(a:resumeFrom, a:end)
  if !lineNumVerb
    return {
      \ 'success': 0,
      \ 'msg': 'Missing query',
    \}
  endif

  """ Parse the next HTTP verb query.
  let resumeFrom = lineNumVerb + 1
  let [lineNumNextVerb, nextRestQuery] = s:ParseVerbQuery(lineNumVerb + 1, a:end)
  if !lineNumNextVerb
    let resumeFrom = a:end + 1
    let lineNumNextVerb = a:end + 1
  endif

  """ Parse headers if any and merge with global headers.
  let localHeaders = s:ParseHeaders(lineNumHost + 1, lineNumVerb - 1)
  let headers = get(a:globSection, 'headers', {})
  call extend(headers, localHeaders)

  """ Parse curl options; local opts overwrite global opts when merged.
  let localCurlOpts = s:ParseCurlOpts(lineNumHost + 1, lineNumVerb - 1)
  let curlOpts = get(a:globSection, 'curlOpts', {})
  call extend(curlOpts, localCurlOpts)

  let vals = get(a:globSection, 'vals', {})

  """ Parse http verb, query path, and data body.
  let [httpVerb; queryPathList] = split(restQuery)
  let dataBody = getline(lineNumVerb + 1, lineNumNextVerb - 1)

  """ Search and replace values in queryPath, dataBody, and headers
  let queryPath = join(queryPathList, '')
  for key in keys(vals)
    let queryPath = substitute(queryPath, ":" . key, vals[key], "")
    call map(dataBody, 'substitute(v:val, ":" . key, vals[key], "")')
    call map(headers,  'substitute(v:val, ":" . key, vals[key], "")')
  endfor

  """ Filter out comment and blank lines.
  call filter(dataBody, 'v:val !~ ''\v^\s*(#|//).*$|\v^\s*$''')

  """ Some might need leading/trailing spaces in body rows.
  "call map(dataBody, 's:StrTrim(v:val)')
  return {
    \ 'success': 1,
    \ 'resumeFrom': resumeFrom,
    \ 'msg': '',
    \ 'host': host,
    \ 'headers': headers,
    \ 'curlOpts': curlOpts,
    \ 'httpVerb': httpVerb,
    \ 'requestPath': queryPath,
    \ 'dataBody': dataBody
  \}
endfunction

"""
" Construct the cUrl command given the request.
"
" @see s:ParseRequest() For a:request.
"
" @param  dict a:request
" @return list [command, dict of curl options]
"
function! s:GetCurlCommand(request)
  """ Construct curl args.
  let curlOpts = vrc#opt#GetDefaultCurlOpts()
  call extend(curlOpts, get(a:request, 'curlOpts', {}))

  let vrcIncludeHeader = s:GetOpt('vrc_include_response_header', 0)
  if vrcIncludeHeader && !vrc#opt#DictHasKeys(curlOpts, ['-i', '--include'])
    let curlOpts['-i'] = ''
  endif

  let vrcDebug = s:GetOpt('vrc_debug', 0)
  if vrcDebug && !has_key(curlOpts, '-v')
    let curlOpts['-v'] = ''
  endif

  " Consider to add -k only if vrc_ssl_secure is configured (secureSsl > -1).
  let secureSsl = s:GetOpt('vrc_ssl_secure', -1)
  if a:request.host =~? '\v^\s*HTTPS://' && secureSsl == 0 && !has_key(curlOpts, '-k')
    let curlOpts['-k'] = ''
  endif

  """ Add --ipv4
  let resolveToIpv4 = s:GetOpt('vrc_resolve_to_ipv4', 0)
  if resolveToIpv4 && !has_key(curlOpts, '--ipv4')
    let curlOpts['--ipv4'] = ''
  endif

  """ Add --cookie-jar
  let cookieJar = s:GetOpt('vrc_cookie_jar', '')
  if !empty(cookieJar)
    if !has_key(curlOpts, '-b')
      let curlOpts['-b'] = cookieJar
    endif
    if !has_key(curlOpts, '-c')
      let curlOpts['-c'] = cookieJar
    endif
  endif

  """ Add -L option to enable redirects
  let locationEnabled = s:GetOpt('vrc_follow_redirects', 0)
  if locationEnabled && !has_key(curlOpts, '-L')
    let curlOpts['-L'] = ''
  endif

  """ Add headers.
  let headerOpt = get(curlOpts, '-H', '')
  if empty(headerOpt)
    let curlOpts['-H'] = []
  elseif type(headerOpt) != type([])
    let curlOpts['-H'] = [headerOpt]
  endif
  for key in keys(a:request.headers)
    call add(curlOpts['-H'], key . ': ' . a:request.headers[key])
  endfor

  """ Timeout options.
  let vrcConnectTimeout = s:GetOpt('vrc_connect_timeout', 0)
  if vrcConnectTimeout && !has_key(curlOpts, '--connect-timeout')
    let curlOpts['--connect-timeout'] = vrcConnectTimeout
  endif

  let vrcMaxTime = s:GetOpt('vrc_max_time', 0)
  if vrcMaxTime && !has_key(curlOpts, '--max-time')
    let curlOpts['--max-time'] = vrcMaxTime
  endif

  """ Convert cUrl options to command line arguments.
  let curlArgs = vrc#opt#DictToCurlArgs(curlOpts)
  call map(curlArgs, 's:EscapeCurlOpt(v:val)')

  """ Add http verb.
  let httpVerb = a:request.httpVerb
  call add(curlArgs, s:GetCurlRequestOpt(httpVerb))

  """ Add data body.
  if !empty(a:request.dataBody)
    call add(curlArgs, s:GetCurlDataArgs(a:request))
  endif
  return [
    \ 'curl ' . join(curlArgs) . ' ' . s:Shellescape(a:request.host . a:request.requestPath),
    \ curlOpts
  \]
endfunction

"""
" Helper function to shell-escape cUrl options.
"
" @param string a:val
"
function! s:EscapeCurlOpt(val)
  return a:val !~ '\v^-' ? s:Shellescape(a:val) : a:val
endfunction

"""
" Get the cUrl option for request method (--get, --head, -X <verb>...)
"
" @param  string a:httpVerb
" @return string
"
function! s:GetCurlRequestOpt(httpVerb)
  if a:httpVerb ==? 'GET'
    if s:GetOpt('vrc_allow_get_request_body', 0)
      return '-X GET'
    endif
    return '--get'
  elseif a:httpVerb ==? 'HEAD'
    return '--head'
  endif
  return '-X ' . a:httpVerb
endfunction

"""
" Get the cUrl option to include data body (--data, --data-urlencode...)
"
" @see s:ParseRequest() For a:request.
"
" @param  dict a:request
" @return string
"
function! s:GetCurlDataArgs(request)
  let httpVerb = a:request.httpVerb
  let dataLines = a:request.dataBody

  let preproc = s:GetOpt('vrc_body_preprocessor', '')

  """ These verbs should have request body passed as POST params.
  if httpVerb ==? 'POST'
    \ || httpVerb ==? 'PUT'
    \ || httpVerb ==? 'PATCH'
    \ || httpVerb ==? 'OPTIONS'
    """ If data is loaded from file.
    if stridx(get(dataLines, 0, ''), '@') == 0
      return '--data-binary ' . s:Shellescape(dataLines[0])
    endif

    """ Call body preprocessor if set.
    if preproc != ''
      let dataLines = systemlist(preproc, join(dataLines, "\r"))
    endif

    """ If request body is split line by line.
    if s:GetOpt('vrc_split_request_body', 0)
      call map(dataLines, '"--data " . s:Shellescape(v:val)')
      return join(dataLines)
    endif

    """ If ElasticSearch support is on and it's a _bulk request.
    let elasticSupport = s:GetOpt('vrc_elasticsearch_support', 0)
    if elasticSupport && match(a:request.requestPath, '/_bulk\|/_msearch') > -1
      " shellescape also escapes \n (<NL>) to \\n, need to replace back.
      return '--data ' .
           \ substitute(
             \ s:Shellescape(join(dataLines, "\n") . "\n"),
             \ '\\\n',
             \ "\n",
             \ 'g'
             \)
    endif

    """ Otherwise, just join data using empty space.
    return '--data ' . s:Shellescape(join(dataLines, ''))
  endif

  """ If verb is GET and GET request body is allowed.
  if httpVerb ==? 'GET' && s:GetOpt('vrc_allow_get_request_body', 0)
    """ Call body preprocessor if set.
    if preproc != ''
      let dataLines = systemlist(preproc, join(dataLines, "\r"))
    endif
    return '--data ' . s:Shellescape(join(dataLines, ''))
  endif

  """ For other cases, request body is passed as GET params.
  if s:GetOpt('vrc_split_request_body', 0)
    """ If request body is split, url-encode each line.
    call map(dataLines, '"--data-urlencode " . s:Shellescape(v:val)')
    return join(dataLines)
  endif
  """ Otherwise, url-encode and send the request body as a whole.
  return '--data-urlencode ' . s:Shellescape(join(dataLines, ''))
endfunction

"""
" Display output in the given buffer name.
"
" @see s:RunQuery() For a:outputInfo.
"
" @param string a:tmpBufName
" @param dict   a:outputInfo {'outputChunks': list[string], 'commands': list[string]}
" @param dict   a:config     {'hasResponseHeader': boolean}
"
function! s:DisplayOutput(tmpBufName, outputInfo, config)
  """ Get view options before working in the view buffer.
  let autoFormatResponse = s:GetOpt('vrc_auto_format_response_enabled', 1)
  let syntaxHighlightResponse = s:GetOpt('vrc_syntax_highlight_response', 1)
  let includeResponseHeader = get(a:config, 'hasResponseHeader', 0)
  let contentType = s:GetOpt('vrc_response_default_content_type', '')

  """ Setup view.
  let origWin = winnr()
  let outputWin = bufwinnr(bufnr(a:tmpBufName))
  if outputWin == -1
    let cmdSplit = 'vsplit'
    if s:GetOpt('vrc_horizontal_split', 0)
      let cmdSplit = 'split'
    endif

    if s:GetOpt('vrc_keepalt', 0)
      let cmdSplit = 'keepalt ' . cmdSplit
    endif

    """ Create view if not loadded or hidden.
    execute 'rightbelow ' . cmdSplit . ' ' . a:tmpBufName
    setlocal buftype=nofile
  else
    """ View already shown, switch to it.
    execute outputWin . 'wincmd w'
  endif

  """ Display output in view.
  setlocal modifiable
  silent! normal! ggdG
  let output = join(a:outputInfo['outputChunks'], "\n\n")
  call setline('.', split(substitute(output, '[[:return:]]', '', 'g'), '\v\n'))

  """ Display commands in quickfix window if any.
  if (!empty(a:outputInfo['commands']))
    execute 'cgetexpr' string(a:outputInfo['commands'])
    copen
    execute outputWin 'wincmd w'
  endif

  """ Detect content-type based on the returned header.
  let emptyLineNum = 0
  if includeResponseHeader
    call cursor(1, 0)
    let emptyLineNum = search('\v^\s*$', 'n')
    let contentTypeLineNum = search('\v\c^Content-Type:', 'n', emptyLineNum)

    if contentTypeLineNum > 0
      let contentType = substitute(
        \ getline(contentTypeLineNum),
        \ '\v\c^Content-Type:\s*([^;[:blank:]]*).*$',
        \ '\1',
        \ 'g'
      \)
    endif
  endif

  """ Continue with options depending content-type.
  if !empty(contentType)
    let fileType = substitute(contentType, '\v^.*/(.*\+)?(.*)$', '\2', 'g')

    """ Auto-format the response.
    if autoFormatResponse
      let formatCmd = s:GetDict('vrc_auto_format_response_patterns', fileType, '')
      if !empty(formatCmd)
        """ Auto-format response body
        let formattedBody = system(
          \ formatCmd,
          \ getline(emptyLineNum, '$')
        \)
        if v:shell_error == 0
          silent! execute (emptyLineNum + 1) . ',$delete _'
          if s:GetOpt('vrc_auto_format_uhex', 0)
            let formattedBody = substitute(
              \ formattedBody,
              \ '\v\\u(\x{4})',
              \ '\=nr2char("0x" . submatch(1), 1)',
              \ 'g'
            \)
          endif
          call append('$', split(formattedBody, '\v\n'))
        elseif s:GetOpt('vrc_debug', 0)
          echom "VRC: auto-format error: " . v:shell_error
          echom formattedBody
        endif
      endif
    endif

    """ Syntax-highlight response.
    if syntaxHighlightResponse
      syntax clear
      try
        execute "syntax include @vrc_" . fileType . " syntax/" . fileType . ".vim"
        execute "syntax region body start=/^$/ end=/\%$/ contains=@vrc_" . fileType
      catch
      endtry
    endif
  endif

  """ Finalize view.
  setlocal nomodifiable
  execute origWin . 'wincmd w'
endfunction

"""
" Run a REST request between the given lines.
"
" @param int a:start
" @param int a:end
"
function! s:RunQuery(start, end)
  let globSection = s:ParseGlobSection()
  let outputInfo = {
    \ 'outputChunks': [],
    \ 'commands': [],
  \}

  " The `while loop` is to support multiple
  " requests using consecutive verbs.
  let resumeFrom = a:start
  let shouldShowCommand = s:GetOpt('vrc_show_command', 0)
  let shouldDebug = s:GetOpt('vrc_debug', 0)
  while resumeFrom < a:end
    let request = s:ParseRequest(a:start, resumeFrom, a:end, globSection)
    if !request.success
      echom request.msg
      return
    endif

    let [curlCmd, curlOpts] = s:GetCurlCommand(request)
    if shouldDebug
      echom '[Debug] Command: ' . curlCmd
      echom '[Debug] cUrl options: ' . string(curlOpts)
    endif
    silent !clear
    redraw!

    call add(outputInfo['outputChunks'], system(curlCmd))
    if shouldShowCommand
      call add(outputInfo['commands'], curlCmd)
    endif
    let resumeFrom = request.resumeFrom
  endwhile

  call s:DisplayOutput(
    \ s:GetOpt('vrc_output_buffer_name', '__REST_response__'),
    \ outputInfo,
    \ {
      \ 'hasResponseHeader': vrc#opt#DictHasKeys(curlOpts, ['-i', '--include'])
    \ }
  \)
endfunction

"""
" Restore the win line to the given previous line.
"
" @param int a:prevLine
"
function! s:RestoreWinLine(prevLine)
  let offset = winline() - a:prevLine
  if !offset
    return
  elseif offset > 0
    exec "normal! " . offset . "\<C-e>"
  else
    exec "normal! " . -offset . "\<C-y>"
  endif
endfunction

"""
" Run a request block that encloses the cursor.
"
function! VrcQuery()
  """ We'll jump pretty much. Save the current win line to set the view as before.
  let curWinLine = winline()

  let curPos = getpos('.')
  if curPos[1] <= s:LineNumGlobSectionDelim()
    echom 'Cannot execute global section'
    return
  endif

  """ Determine the REST request block to process.
  let [blockStart, blockEnd] = s:LineNumsRequestBlock()
  if !blockStart
    call s:RestoreWinLine(curWinLine)
    echom 'Missing host/block start'
    return
  endif

  """ Parse and execute the query
  call s:RunQuery(blockStart, blockEnd)
  call s:RestoreWinLine(curWinLine)

  """ Display deprecated message if any.
  if !empty(s:deprecatedMessages)
    for msg in s:deprecatedMessages
      echohl WarningMsg | echo msg | echohl None
    endfor
    let s:deprecatedMessages = []
  endif
endfunction

"""
" Do the key map.
"
function! VrcMap()
  let triggerKey = s:GetOpt('vrc_trigger', '<C-j>')
  execute 'vnoremap <buffer> ' . triggerKey . ' :call VrcQuery()<CR>'
  execute 'nnoremap <buffer> ' . triggerKey . ' :call VrcQuery()<CR>'
  execute 'inoremap <buffer> ' . triggerKey . ' <Esc>:call VrcQuery()<CR>'
endfunction

if s:GetOpt('vrc_set_default_mapping', 1)
  call VrcMap()
endif
