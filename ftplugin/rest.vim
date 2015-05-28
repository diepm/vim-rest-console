function! s:GetOptValue(opt, defVal)
    if exists('b:' . a:opt)
        return eval('b:' . a:opt)
    endif
    if exists('g:' . a:opt)
        return eval('g:' . a:opt)
    endif
    return a:defVal
endfunction

function! s:ParseRequest(listLines)
    """ Filter comments.
    call filter(a:listLines, 'v:val !~ ''\v^\s*(#|//)''')

    """ Parse host.
    let numLines = len(a:listLines)
    let host = ''
    let useSsl = 0
    let i = 0
    while i < numLines
        let line = substitute(a:listLines[i], '\s+', '', 'g')
        let i += 1
        if line =~? '\v^HTTPS?\://'
            let host = line
            if host =~? '\v^HTTPS'
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

    """ Parse REST query.
    let restQuery = ''
    while i < numLines
        let line = substitute(a:listLines[i], '\v^\s*(.*)\s*$', '\1', '')
        let i += 1
        if line =~? '\v^(GET|POST|PUT|DELETE|HEAD)\s+'
            let restQuery = line
            break
        endif
    endwhile
    if empty(restQuery)
        return {
        \   'success': 0,
        \   'msg': 'Missing query',
        \}
    endif

    """ Parse http verb and query path.
    let [httpVerb, queryPath; urlEncodeData] = split(restQuery)
    let nlSepBodyPattern = join(
    \   s:GetOptValue('vrc_nl_sep_post_data_patterns', ['\v\W?_bulk\W?']),
    \   '|'
    \)
    let joinSep = (queryPath =~ nlSepBodyPattern) ? "\n" : ''
    return {
    \   'success': 1,
    \   'msg': '',
    \   'host': host,
    \   'useSsl': useSsl,
    \   'httpVerb': httpVerb,
    \   'requestPath': queryPath,
    \   'urlEncodeData': join(urlEncodeData),
    \   'dataBody': join(a:listLines[i :], joinSep)
    \}
endfunction

function! s:CallCurl(request)
    """ Construct CURL args.
    let curlArgs = ['-isS']
    let vrcDebug = s:GetOptValue('vrc_debug', 0)
    if vrcDebug
        call add(curlArgs, '-v')
    endif
    let secureSsl = s:GetOptValue('vrc_ssl_secure', 0)
    if a:request.useSsl && !secureSsl
        call add(curlArgs, '-k')
    endif

    """ Add headers.
    let contentType = s:GetOptValue('vrc_header_content_type', 'application/json')
    call add(curlArgs, '-H ' . shellescape('Content-Type: ' . contentType))

    """ Add http verb.
    let httpVerb = a:request.httpVerb
    if httpVerb ==? 'GET'
        call add(curlArgs, '--get')
    elseif httpVerb ==? 'HEAD'
        call add(curlArgs, '--head')
    else
        call add(curlArgs, '-X ' . httpVerb)
    endif

    """ Add --data-urlencode for GET and HEAD.
    let verbGetOrHead = httpVerb ==? 'GET' || httpVerb ==? 'HEAD'
    if !empty(a:request.urlEncodeData) && verbGetOrHead
        call add(curlArgs, '--data-urlencode ' . shellescape(a:request.urlEncodeData))
    endif

    """ Add data body.
    if !empty(a:request.dataBody)
        let dataOpt = verbGetOrHead ? '--data-urlencode' : '--data'
        call add(curlArgs, dataOpt . ' ' . shellescape(a:request.dataBody))
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

function! VrcQuery() range
    """ Determine the REST request block to process.
    let bufStart = 0
    let bufEnd = 0
    if a:firstline < a:lastline
        """ Use range if given.
        let bufStart = a:firstline
        let bufEnd = a:lastline
    else
        """ Find the request block the cursor stays within.
        let bufStart = line('.')
        if getline('.') !~? '\v^\s*HTTPS?\://'
            let bufStart = search('\c\v^\s*HTTPS?\://', 'bn')
            if !bufStart
                echom 'Missing host'
                return
            endif
        endif

        """ Find the start of the next request block.
        let bufEnd = search('\c\v^\s*HTTPS?\://', 'n') - 1
        if bufEnd <= bufStart
            let bufEnd = line('$')
        endif
    endif
    call s:RunQuery(getline(bufStart, bufEnd))
endfunction

function! VrcMap()
    let triggerKey = s:GetOptValue('vrc_trigger', '<C-j>')
    execute 'vnoremap ' . triggerKey . ' :call VrcQuery()<CR>'
    execute 'nnoremap ' . triggerKey . ' <Esc>:call VrcQuery()<CR>'
    execute 'inoremap ' . triggerKey . ' <Esc>:call VrcQuery()<CR>'
endfunction

call VrcMap()
