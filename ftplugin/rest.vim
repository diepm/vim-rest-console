let s:vrc_auto_format_response_patterns = {
\   'json': 'python -m json.tool',
\   'xml': 'xmllint --format -',
\}

let s:vrc_block_delimiter = '\c\v^\s*HTTPS?://|^---'

function! s:StrStrip(txt)
    return substitute(a:txt, '\v^\s*(.*)\s*$', '\1', 'g')
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

function! s:ParseRequest(listLines)
    """ Filter comments.
    call filter(a:listLines, 'v:val !~ ''\v^\s*(#|//|---)?$''')

    """ Parse host.
    let numLines = len(a:listLines)
    let host = ''
    let useSsl = 0
    let i = 0
    while i < numLines
        let line = substitute(a:listLines[i], '\s+', '', 'g')
        let i += 1
        if line =~? '\v^\s*HTTPS?://'
            let host = line
            if host =~? '\v^\s*HTTPS://'
                let useSsl = 1
            endif
            break
        endif
    endwhile
    if empty(host)
        return {
        \   'success': 0,
        \   'msg': 'Missing host',
        \}
    endif

    """ Parse REST query and request headers.
    let restQuery = ''
    let headers = {}
    while i < numLines
        let line = s:StrStrip(a:listLines[i])
        let i += 1
        """ Http verb is reached, get out of loop.
        if line =~? '\v^(GET|POST|PUT|DELETE|HEAD)\s+'
            let restQuery = line
            break
        endif

        """ Otherwise, parse header line.
        let sepIdx = stridx(line, ':')
        if sepIdx > -1
            let headerKey = s:StrStrip(line[0:sepIdx - 1])
            let headerVal = s:StrStrip(line[sepIdx + 1:])
            let headers[headerKey] = headerVal
        endif
    endwhile
    if empty(restQuery)
        return {
        \   'success': 0,
        \   'msg': 'Missing query',
        \}
    endif

    """ Parse http verb and query path.
    let [httpVerb; queryPath] = split(restQuery)
    return {
    \   'success': 1,
    \   'msg': '',
    \   'host': host,
    \   'useSsl': useSsl,
    \   'headers': headers,
    \   'httpVerb': httpVerb,
    \   'requestPath': join(queryPath, ''),
    \   'dataBody': join(a:listLines[i :], '')
    \}
endfunction

function! s:CallCurl(request)
    """ Construct CURL args.
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
    if a:request.useSsl && !secureSsl
        call add(curlArgs, '-k')
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
    let hasContentType = 0
    for key in keys(a:request.headers)
        if key ==? 'Content-Type'
            let hasContentType = 1
        endif
        call add(curlArgs, '-H ' . shellescape(key . ': ' . a:request.headers[key]))
    endfor
    if !hasContentType
        let contentType = s:GetOptValue('vrc_header_content_type', 'application/json')
        call add(curlArgs, '-H ' . shellescape('Content-Type: ' . contentType))
    endif

    """ Add http verb.
    let httpVerb = a:request.httpVerb
    if httpVerb ==? 'GET'
        call add(curlArgs, '--get')
    elseif httpVerb ==? 'HEAD'
        call add(curlArgs, '--head')
    elseif httpVerb !=? 'POST'
        """ Use -X/--request for any verbs other than POST.
        call add(curlArgs, '-X ' . httpVerb)
    endif

    """ Add data body.
    if !empty(a:request.dataBody)
        let dataBody = shellescape(a:request.dataBody)
        if httpVerb ==? 'GET' || httpVerb ==? 'HEAD' || httpVerb ==? 'DELETE'
            """ These verbs should not have request body. Make it as GET params.
            call add(curlArgs, '--data-urlencode ' . dataBody)
        elseif httpVerb ==? 'POST' || httpVerb ==? 'PUT'
            """ Should load from a file? (dataBody is already shell-escaped).
            if stridx(dataBody, '@') == 1
                """ Load from a file.
                call add(curlArgs, '--data-binary ' . dataBody)
            else
                call add(curlArgs, '--data ' . dataBody)
            endif
        endif
    endif

    """ Execute the CURL command.
    let curlCmd = 'curl ' . join(curlArgs) . ' ' . shellescape(a:request.host . a:request.requestPath)
    if vrcDebug
        echom curlCmd
    endif
    silent !clear
    redraw!
    return system(curlCmd)
endfunction

function! s:DisplayOutput(tmpBufName, output)
    """ Get view options before working in the view buffer.
    let autoFormatResponse = s:GetOptValue('vrc_auto_format_response_enabled', 1)
    let syntaxHighlightResponse = s:GetOptValue('vrc_syntax_highlight_response', 1)

    """ Setup view.
    let origWin = winnr()
    let outputWin = bufwinnr(bufnr(a:tmpBufName))
    if outputWin == -1
        """ Create view if not loadded or hidden.
        execute 'rightbelow vsplit ' . a:tmpBufName
        setlocal buftype=nofile
    else
        """ View already shown, switch to it.
        execute outputWin . 'wincmd w'
    endif

    """ Display output in view.
    setlocal modifiable
    silent! normal! ggdG
    call setline('.', split(substitute(a:output, '[[:return:]]', '', 'g'), '\v\n'))

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
        let fileType = substitute(contentType, '\v^.*/(.*\+)?(.*)$', '\2', 'g')

        """ Auto-format the response.
        if autoFormatResponse
            let formatCmd = s:GetDictValue('vrc_auto_format_response_patterns', fileType, '')

            if !empty(formatCmd)
                """ Auto-format response body
                let formattedBody = system(
                \   formatCmd,
                \   join(getline(emptyLineNum + 0, '$'), "\n")
                \)
                if v:shell_error == 0
                    execute (emptyLineNum + 1) . ',$delete _'
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

    setlocal nomodifiable
    execute origWin . 'wincmd w'
endfunction

function! s:RunQuery(textLines)
    let request = s:ParseRequest(a:textLines)
    if !request.success
        echom request.msg
        return
    endif
    call s:DisplayOutput(
    \   s:GetOptValue('vrc_output_buffer_name', '__REST_response__'),
    \   s:CallCurl(request)
    \)
endfunction

function! VrcQuery()
    """ Remember the cursor position as we're going to jump around
    let l:cursor_position = getpos('.')

    """ Determine the REST request block to process.
    let blockStart = 0
    let blockEnd = 0

    """ Find the request block the cursor stays within.
    normal! $
    let blockStart = search(s:vrc_block_delimiter, 'bn')
    if !blockStart
        echom 'Missing host/block start'
        """ Restore the cursor position before returning
        call cursor(l:cursor_position[1], l:cursor_position[2])
        return
    endif

    """ Find the start of the next request block.
    let blockEnd = search(s:vrc_block_delimiter, 'n') - 1
    if blockEnd <= blockStart
        let blockEnd = line('$')
    endif

    let queryBlock = getline(blockStart, blockEnd)

    """ Extract the global definitions and prepend to the queryBlock
    """ definition if the block starts with ---
    if getline(blockStart) =~? '\v^---'
        normal! gg
        let globalEnd = search('\v^---', 'n') - 1
        if globalEnd
            let queryBlock = getline(0, globalEnd) + queryBlock
        endif
    endif

    """ Restore the cursor position before parsing the queryBlock
    call cursor(l:cursor_position[1], l:cursor_position[2])

    """ Parse and execute the query
    call s:RunQuery(queryBlock)
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

