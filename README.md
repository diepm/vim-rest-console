# Vim REST Console (VRC)

### 1. Introduction

**VRC** is a Vim plug-in to help send requests to and display responses from
RESTful services in Vim. It's useful for working with REST services that use
JSON to exchange information between server and client such as ElasticSearch.

VRC can also be used as a cURL client for simple needs such as getting a
HTTP page response or posting to a form.

Requirements:

* cURL
* Vim 7.4 (might work with the older Vim versions)

### 2. Features

* Execute REST request and display the response on a separate display buffer.
* Make changing/adjusting request body easy.
* Can have multiple REST request blocks per VRC buffer.
* Can have multiple VRC buffers where they all share the same output buffer or
  each can have its own output buffer.
* Particularly useful for working with REST services that require the request
  body to be sent in JSON such as ElasticSearch.
* Syntax highlighting.

### 3. Installation

VRC requires [cURL](http://curl.haxx.se/). It's tested with Vim 7.4 but might
work with the older versions.

To install using [pathogen.vim](https://github.com/tpope/vim-pathogen)

    cd ~/.vim/bundle
    git clone https://github.com/diepm/vim-rest-console.git

To install using [Vundle](https://github.com/gmarik/Vundle.vim)

    " Add this line to .vimrc
    Plugin 'diepm/vim-rest-console'

### 4. Examples

For more examples, check out

https://raw.githubusercontent.com/diepm/vim-rest-console/master/sample.rest

there is also an alternative version using global settings:

https://raw.githubusercontent.com/diepm/vim-rest-console/master/sample_global.rest

The following examples assume that an ElasticSearch service is running at
localhost. The pipe (`|`) indicates the current position of the cursor.

#### 4.1 Single VRC Buffer

* From the command line, run a new Vim instance.
* Set the buffer `filetype` to `rest` by

    ```
    :set ft=rest
    ```

* Type in

    ```
    http://localhost:9200
    GET /_cat/nodes?v|
    ```

* Hit the trigger key (`<C-j>` by default).
* A new vertically split buffer will be shown to display the output.
* Change the request block to (or add another one)

    ```
    http://localhost:9200
    POST /testindex/testtype
    {
      "key": "new key",
      "value": "new value"|
    }
    ```

* Hit the trigger key with the cursor placed anywhere within this request block.
* The display buffer will be updated with the new response.

#### 4.2 Multiple VRC Buffers

This example continues the previous one.

* Open a new VRC buffer in a new tab

    ```
    :tabe NewVrc.rest
    ```

* Since the new buffer has the extension `rest`, the VRC plug-in is active for
  this one.
* Set `b:vrc_output_buffer_name` of this buffer to `__NEW_VRC__`

    ```
    :let b:vrc_output_buffer_name = '__NEW_VRC__'
    ```

* Type in a request block such as

    ```
    http://localhost:9200
    GET /testindex/_search?pretty|
    ```

* Hit the trigger key.
* A new display buffer will be created showing the response.
* Go back to the VRC buffer of the previous example (previous tab).
* Try to execute an existing request block.
* The corresponding display buffer will be updated.

### 5. Usage

This plug-in is activated when Vim opens a buffer of type `rest`. This may be
a file with the extension `.rest` or a buffer with `filetype` explicitly set to
`rest` by

    :set ft=rest

A **VRC buffer** can have one or many REST request blocks. A **request block**
contains a *host*, *optional headers*, *query*, and an *optional request body*
(usually used by POST). A block is defined as follows.

    # host
    http[s]://domain[:port]

    [optional headers]

    # query
    POST /path/to/resource
    [optional request body]

A comment starts with `#` or `//` and must be on its own line. The following
is an example of a VRC buffer with multiple request blocks.

    # GETting from resource.
    http://example.com
    GET /path/to/resource?key=value

    # POSTing to an ElasticSearch service.
    http://example.com/elasticsearch

    // Specify optional headers.
    Content-Type: application/json; charset=utf-8

    POST /index/type?pretty
    {
        "key": "a key",
        "value": "a value"
    }

    # Submitting a form.
    https://example.net:8080

    Accept: */*
    Authorization: Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==
    Cache-Control: no-cache
    Connection: keep-alive
    Content-Type: application/x-www-form-urlencoded
    Cookie: userId=ac32:dfbe:8f1a:249c; sid=cfb48e3d98fcb1
    User-Agent: VRC

    POST /form
    var1=value of var1&
    var2=value of var2

When the trigger key is called (`<C-j>` by default), VRC processes the request
block that the cursor stays within. The response is displayed in a new
vertically split buffer. This output buffer is reused if it's already present.

By default, the display/output buffer is named `__REST_response__`. If there
are multiple VRC buffers, they all share the same display buffer. To have a
separate output display for each VRC buffer, `b:vrc_output_buffer_name` can be
set in the buffer scope.

#### 5.1 Global Definitions

A recent addition to VRC are optional global definitions. The global part is
separated from the rest with two dashes `--` and may include a default host
and optional default headers. These values are always included in each
request.

Each request block has to start with either two dashes indicating it uses the
default host from the global section or any host only used by this block. If
a 'local host' is given, it's used instead of the one specified in the global
section. Additionally, a request block can specify extra headers that will be
merged with any global headers. Local headers overwrite global headers.

    # Global definitions.
    // Default host.
    https://domain[:port]/...

    // Default headers.
    Accept: application/json
    X-Header: Custom Data
    --

    # Request block that uses default values from the global section.
    --
    GET /some/query

    # Request block that specifies its own host and extra headers.
    // Local host.
    http://example.net:9200

    // Extra headers.
    Xtra-Header: Some Extra.
    // This header will overwrite the one in the global section.
    X-Header: New Data

    POST /service
    var1=value

### 6. Configuration

VRC supports a few configurable variables. Each of them can have a global or
buffer scope (the latter takes priority). An option can be set in `.vimrc` for
the global scope by

    let g:option_name = value

or in Vim for the buffer scope by

    let b:option_name = value

#### `vrc_trigger`

This option defines the trigger key. It's `<C-j>` by default. To remap the key,

    let g:vrc_trigger = '<C-k>'

#### `vrc_ssl_secure`

This option tells cURL to check or not check for the SSL certificates. It's
turned off by default. To enable,

    let g:vrc_ssl_secure = 1

#### `vrc_output_buffer_name`

This option sets the name for the output/display buffer. By default, it's set
to `__REST_response__`. To assign a different name,

    let g:vrc_output_buffer_name = '__NEW_NAME__'

This option is useful in working with multiple VRC buffers where each one has
its own output display. For this, the option can be set in the buffer scope as

    let b:vrc_output_buffer_name = '__REST_1_OUTPUT__'

#### `vrc_header_content_type`

This option is to set the header content type of the request. It defaults to
`application/json`. To set a different default content type,

    let g:vrc_header_content_type = 'application/x-www-form-urlencoded'

It can also be set in the buffer scope by

    let b:vrc_header_content_type = 'application/json; charset=utf-8'

If `Content-Type` is specified in the request block, it overrides this setting.

#### `vrc_cookie_jar`

This option enables persisting cookies between requests in a cookie jar file.
Useful when the underlying API uses session or authorization cookies.

    let g:vrc_cookie_jar = '/tmp/vrc_cookie_jar'

It can also be set in the buffer scope by

    let b:vrc_cookie_jar = './jar'

#### `vrc_set_default_mapping`

This option is to enable/disable the trigger key mapping. It's enabled by
default. To disable the mapping,

    let g:vrc_set_default_mapping = 0

Once the mapping is disabled, the request block can be executed by

    :call VrcQuery()

#### `vrc_follow_redirects`

This option enables the cURL -L/--location option that makes it follow
redirects. It's turned off by default. To enable

    let g:vrc_follow_redirects = 1

#### `vrc_include_response_header`

This option enables the inclusion of the response header information mode by
adding the `-i` option to the *curl* command. It's turned on by default. To
disable

    let g:vrc_include_response_header = 0

If this option is disabled, the following options will not take effect.

* `vrc_auto_format_response_enabled`
* `vrc_auto_format_response_patterns`
* `vrc_syntax_highlight_response`

#### `vrc_auto_format_response_enabled`

This option enables the automatic formatting of the response. It's enabled by
default. To disable:

    let g:vrc_auto_format_response_enabled = 0

If `vrc_include_response_header` is disabled, this option does nothing.

#### `vrc_auto_format_response_patterns`

This option defines which external tools to use to auto-format the response
body according to the Content-Type.

The defaults are:

    let s:vrc_auto_format_response_patterns = {
    \   'json': 'python -m json.tool',
    \   'xml': 'xmllint --format -',
    \}

Adjust the list by defining the global or buffer variable, like so:

    let g:vrc_auto_format_response_patterns = {
    \   'json': ''
    \   'xml': 'tidy -xml -i -'
    \}

If `vrc_include_response_header` is disabled, this option does nothing.

#### `vrc_syntax_highlight_response`

This option enables the syntax highlighting of the response body according to
the Content-Type. It's enabled by default. To disable:

    let g:vrc_syntax_highlight_response = 0

If `vrc_include_response_header` is disabled, this option does nothing.

#### `vrc_connect_timeout`

Corresponding to cUrl option `--connect-timeout`. Default: 10 seconds.

#### `vrc_max_time`

Corresponding to cUrl option `--max-time`. Default: 60 seconds.

#### `vrc_debug`

This option enables the debug mode by adding the `-v` option to the *curl*
command and also `echom` the command to the Vim console. It's turned off by
default.

### 7. Tips 'n Tricks

#### 7.1 POST Data in Bulk

Since v2.0, VRC supports POSTing data in bulk using an external data file.
It's helpful for such APIs as ElasticSearch's Bulk API.

    http://localhost:9200
    POST /testindex/_bulk
    @data.sample.json

#### 7.2 Syntax Highlighting

Though VRC supports output syntax highlighting, it's based on the response
Content-Type. When Content-Type is not present, the output can still be
syntax-highlighted if the appropriate ftplugin is installed. To force the
output highlighting based on `filetype`, place this setting in `.vimrc`:

    let g:vrc_output_buffer_name = '__VRC_OUTPUT.<filetype>'

`filetype` can also be set in the output buffer on an ad hoc basis.

    # vim: set ft=json

### 8. Contributors

Thanks to the contributors (in alphabetical order)

    @dan-silva
    @jojoyuji
    @korin
    @mjakl
    @sethtrain
    @shanesmith
    @tonyskn
    @torbjornvatn

### 9. Changelog

#### 2.1.0 (2016-01-25)

* Support default values specified in a global section.
* Add options for connection and max timeout.

#### 2.0.0 (2015-11-24)

* Support POST data from external files.
* Proper use of cURL commands for HTTP verbs.
* Request body is sent based on HTTP verbs.
  - GET, HEAD, DELETE: as GET params.
  - POST, PUT: as POST params.
* Remove awkward syntaxes.
  - Option `vrc_nl_sep_post_data_patterns` removed.
  - GET params can be specified in request body.

### 10. License

MIT
