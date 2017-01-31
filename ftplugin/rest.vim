setlocal commentstring=#%s

let s:vrc_auto_format_response_patterns = {
\   'json': 'python -m json.tool',
\   'xml': 'xmllint --format -',
\}

let s:vrc_glob_delim      = '\v^--\s*$'
let s:vrc_comment_delim   = '\c\v^\s*(#|//)'
let s:vrc_block_delimiter = '\c\v^\s*HTTPS?://|^--'

function! s:StrTrim(txt)
    return substitute(a:txt, '\v^\s*([^[:space:]].*[^[:space:]])\s*$', '\1', 'g')
endfunction

function! s:GetOptValue(opt, defVal)
    if exists('b:' . a:opt)
        return eval('b:' . a:opt)
    endif
    if exists('g:' . a:opt)
        return eval('g:' . a:opt)
    endif
    return a:defVal
endfunction

function! s:GetDictValue(dictName, key, defVal)
    for prefix in ['b', 'g', 's']
        let varName = prefix . ':' . a:dictName
        if exists(varName) && has_key(eval(varName), a:key)
            return get(eval(varName), a:key)
        endif
    endfor
    return a:defVal
endfunction

"""
" @return [int, int] First and last line of the enclosing request block.
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
" @return [line num or 0, string]
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
" @return [int, string]
"
function! s:ParseVerbQuery(start, end)
    let curPos = getpos('.')
    call cursor(a:start, 1)
    let lineNum = search(
    \   '\c\v^(GET|POST|PUT|DELETE|HEAD|PATCH|OPTIONS|TRACE)\s+',
    \   'cn',
    \   a:end
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
" @return dict
"
function! s:ParseHeaders(start, end)
    let contentTypeOpt = s:GetOptValue('vrc_header_content_type', 'application/json')
    let headers = {'Content-Type': contentTypeOpt}
    if (a:end < a:start)
        return headers
    endif

    let lineBuf = getline(a:start, a:end)
    let hasContentType = 0
    for line in lineBuf
        let line = s:StrTrim(line)
        if line ==? '' || line =~? s:vrc_comment_delim
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
" Parse values in global section
"
" @return dict
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
            let vals[key] = s:StrTrim(line[sepIdx + 1:])
        endif
    endfor
    return vals
endfunction

"""
" @return dict { 'host': String, 'headers': {}, 'vals': {} }
"
function! s:ParseGlobSection()
    let globSection = {
    \   'host': '',
    \   'headers': {},
    \   'vals': {},
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

    """ Parse global vals.
    let vals = s:ParseVals(hostLine + 1, lastLine - 1)

    let globSection = {
    \   'host': host,
    \   'headers': headers,
    \   'vals': vals,
    \}
    return globSection
endfunction

"""
" @param  int start
" @param  int resumeFrom (inclusive)
" @param  int end (inclusive)
" @param  dict globSection
" @return dict
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
        \   'success': 0,
        \   'msg': 'Missing host',
        \}
    endif

    """ Parse the HTTP verb query.
    let [lineNumVerb, restQuery] = s:ParseVerbQuery(a:resumeFrom, a:end)
    if !lineNumVerb
        return {
        \   'success': 0,
        \   'msg': 'Missing query',
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

    let vals = get(a:globSection, 'vals', {})

    """ Parse http verb, query path, and data body.
    let [httpVerb; queryPathList] = split(restQuery)
    let dataBody = getline(lineNumVerb + 1, lineNumNextVerb - 1)

    """ Search and replace values in queryPath
    let queryPath = join(queryPathList, '')
    for key in keys(vals)
        let queryPath = substitute(queryPath, ":" . key, vals[key], "")
    endfor

    """ Filter out comment and blank lines.
    call filter(dataBody, 'v:val !~ ''\v^\s*(#|//).*$|\v^\s*$''')

    """ Some might need leading/trailing spaces in body rows.
    "call map(dataBody, 's:StrTrim(v:val)')
    return {
    \   'success': 1,
    \   'resumeFrom': resumeFrom,
    \   'msg': '',
    \   'host': host,
    \   'headers': headers,
    \   'httpVerb': httpVerb,
    \   'requestPath': queryPath,
    \   'dataBody': dataBody
    \}
endfunction

"""
" Construct the cUrl command given the request.
"
function! s:GetCurlCommand(request)
    """ Construct curl args.
    let curlArgs = ['-sS']

    let vrcIncludeHeader = s:GetOptValue('vrc_include_response_header', 1)
    if vrcIncludeHeader
        call add(curlArgs, '-i')
    endif

    let vrcDebug = s:GetOptValue('vrc_debug', 0)
    if vrcDebug
        call add(curlArgs, '-v')
    endif

    let secureSsl = s:GetOptValue('vrc_ssl_secure', 0)
    if a:request.host =~? '\v^\s*HTTPS://' && !secureSsl
        call add(curlArgs, '-k')
    endif

    """ Add --ipv4
    let resolveToIpv4 = s:GetOptValue('vrc_resolve_to_ipv4', 0)
    if resolveToIpv4
        call add(curlArgs, '--ipv4')
    endif

    """ Add --cookie-jar
    let cookieJar = s:GetOptValue('vrc_cookie_jar', 0)
    if !empty(cookieJar)
        call add(curlArgs, '-b ' . shellescape(cookieJar))
        call add(curlArgs, '-c ' . shellescape(cookieJar))
    endif

    """ Add -L option to enable redirects
    let locationEnabled = s:GetOptValue('vrc_follow_redirects', 0)
    if locationEnabled
      call add(curlArgs, '-L')
    endif

    """ Add headers.
    for key in keys(a:request.headers)
        call add(curlArgs, '-H ' . shellescape(key . ': ' . a:request.headers[key]))
    endfor

    """ Timeout options.
    call add(curlArgs, '--connect-timeout ' . s:GetOptValue('vrc_connect_timeout', 10))
    call add(curlArgs, '--max-time ' . s:GetOptValue('vrc_max_time', 60))

    """ Add http verb.
    let httpVerb = a:request.httpVerb
    call add(curlArgs, s:GetCurlRequestOpt(httpVerb))

    """ Add data body.
    let dataBody = a:request.dataBody
    if !empty(dataBody)
        call add(
        \   curlArgs,
        \   s:GetCurlDataArgs(httpVerb, dataBody)
        \)
    endif
    return 'curl ' . join(curlArgs) . ' ' . shellescape(a:request.host . a:request.requestPath)
endfunction

"""
" Get the cUrl option for request method (--get, --head, -X <verb>...)
"
function! s:GetCurlRequestOpt(httpVerb)
    if a:httpVerb ==? 'GET'
        if s:GetOptValue('vrc_allow_get_request_body', 0)
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
" @param  dict httpVerb
" @param  list dataLines
" @return string
"
function! s:GetCurlDataArgs(httpVerb, dataLines)
    """ These verbs should have request body passed as POST params.
    if a:httpVerb ==? 'POST'
    \  || a:httpVerb ==? 'PUT'
    \  || a:httpVerb ==? 'PATCH'
    \  || a:httpVerb ==? 'OPTIONS'
        """ If data is loaded from file.
        if stridx(get(a:dataLines, 0, ''), '@') == 0
            return '--data-binary ' . shellescape(a:dataLines[0])
        endif

        """ If request body is split line by line.
        if s:GetOptValue('vrc_split_request_body', 0)
            call map(a:dataLines, '"--data " . shellescape(v:val)')
            return join(a:dataLines)
        endif

        """ Otherwise, send the request body as a whole.
        return '--data ' . shellescape(join(a:dataLines, ''))
    endif

    """ If verb is GET and GET request body is allowed.
    if a:httpVerb ==? 'GET' && s:GetOptValue('vrc_allow_get_request_body', 0)
        return '--data ' . shellescape(join(a:dataLines, ''))
    endif

    """ For other cases, request body is passed as GET params.
    if s:GetOptValue('vrc_split_request_body', 0)
        """ If request body is split, url-encode each line.
        call map(a:dataLines, '"--data-urlencode " . shellescape(v:val)')
        return join(a:dataLines)
    endif
    """ Otherwise, url-encode and send the request body as a whole.
    return '--data-urlencode ' . shellescape(join(a:dataLines, ''))
endfunction

"""
" @param string tmpBufName
" @param dict outputInfo
"   {
"     'outputChunks': list[string],
"     'commands': list[string],
"   }
"
function! s:DisplayOutput(tmpBufName, outputInfo)
    """ Get view options before working in the view buffer.
    let autoFormatResponse = s:GetOptValue('vrc_auto_format_response_enabled', 1)
    let syntaxHighlightResponse = s:GetOptValue('vrc_syntax_highlight_response', 1)
    let includeResponseHeader = s:GetOptValue('vrc_include_response_header', 1)
    let contentType = s:GetOptValue('vrc_response_default_content_type', '')

    """ Setup view.
    let origWin = winnr()
    let outputWin = bufwinnr(bufnr(a:tmpBufName))
    if outputWin == -1
        let cmdSplit = 'vsplit'
        if s:GetOptValue('vrc_horizontal_split', 0)
            let cmdSplit = 'split'
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
            \   getline(contentTypeLineNum),
            \   '\v\c^Content-Type:\s*([^;[:blank:]]*).*$',
            \   '\1',
            \   'g'
            \)
        endif
    endif

    """ Continue with options depending content-type.
    if !empty(contentType)
        let fileType = substitute(contentType, '\v^.*/(.*\+)?(.*)$', '\2', 'g')

        """ Auto-format the response.
        if autoFormatResponse
            let formatCmd = s:GetDictValue('vrc_auto_format_response_patterns', fileType, '')
            if !empty(formatCmd)
                """ Auto-format response body
                let formattedBody = system(
                \   formatCmd,
                \   getline(emptyLineNum, '$')
                \)
                if v:shell_error == 0
                    silent! execute (emptyLineNum + 1) . ',$delete _'
                    if s:GetOptValue('vrc_auto_format_uhex', 0)
                        let formattedBody = substitute(
                        \   formattedBody,
                        \   '\v\\u(\x{4})',
                        \   '\=nr2char("0x" . submatch(1), 1)',
                        \   'g'
                        \)
                    endif
                    call append('$', split(formattedBody, '\v\n'))
                elseif s:GetOptValue('vrc_debug', 0)
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

function! s:RunQuery(start, end)
    let globSection = s:ParseGlobSection()
    let outputInfo = {
    \   'outputChunks': [],
    \   'commands': [],
    \}

    " The `while loop` is to support multiple
    " requests using consecutive verbs.
    let resumeFrom = a:start
    let shouldShowCommand = s:GetOptValue('vrc_show_command', 0)
    let shouldDebug = s:GetOptValue('vrc_debug', 0)
    while resumeFrom < a:end
        let request = s:ParseRequest(a:start, resumeFrom, a:end, globSection)
        if !request.success
            echom request.msg
            return
        endif

        let curlCmd = s:GetCurlCommand(request)
        if shouldDebug
            echom curlCmd
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
    \   s:GetOptValue('vrc_output_buffer_name', '__REST_response__'),
    \   outputInfo
    \)
endfunction

"""
" Restore the win line to the given previous line.
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
endfunction

function! VrcMap()
    let triggerKey = s:GetOptValue('vrc_trigger', '<C-j>')
    execute 'vnoremap <buffer> ' . triggerKey . ' :call VrcQuery()<CR>'
    execute 'nnoremap <buffer> ' . triggerKey . ' :call VrcQuery()<CR>'
    execute 'inoremap <buffer> ' . triggerKey . ' <Esc>:call VrcQuery()<CR>'
endfunction

if s:GetOptValue('vrc_set_default_mapping', 1)
    call VrcMap()
endif

