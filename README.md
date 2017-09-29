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
* Supported verbs: GET, POST, PUT, HEAD, PATCH, OPTIONS, and TRACE.

### 3. Installation

VRC requires [cURL](http://curl.haxx.se/). It's tested with Vim 7.4 but might
work with the older versions.

To install using [pathogen.vim](https://github.com/tpope/vim-pathogen)

    cd ~/.vim/bundle
    git clone https://github.com/diepm/vim-rest-console.git

To install using [Vundle](https://github.com/gmarik/Vundle.vim)

    " Add this line to .vimrc
    Plugin 'diepm/vim-rest-console'

Other methods should work as well.

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
contains a *host*, *optional cUrl options*, *optional headers*, *query*, and an
*optional request body* (usually used by POST). A block is defined as follows.

    # host
    http[s]://domain[:port]

    [optional cUrl options]

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

#### 5.1 cUrl Options

A recent addition to VRC is the ability to specify cUrl options. These may be
specified by the VRC option `vrc_curl_opts` or declaring in the
[global section](#52-global-definitions) of a REST buffer and request blocks.

All specified cUrl options are merged together when a cUrl command is built.
For the same keys (cUrl switch) specified at different scopes, the ones of the
request blocks overwrite the ones in the global section then overwrite the
ones defined by `vrc_curl_opts`.

For the deprecated VRC options, they can be replaced by cUrl options. For
example, assuming they have been defined as follows.

    let g:vrc_connect_timeout = 10
    let g:vrc_cookie_jar = '/path/to/cookie'
    let g:vrc_follow_redirects = 1
    let g:vrc_include_response_header = 1
    let g:vrc_max_time = 60
    let g:vrc_resolve_to_ipv4 = 1
    let g:vrc_ssl_secure = 1

Using cUrl options,

    let g:vrc_curl_opts = {
      \ '--connect-timeout' : 10,
      \ '-b': '/path/to/cookie',
      \ '-c': '/path/to/cookie',
      \ '-L': '',
      \ '-i': '',
      \ '--max-time': 60,
      \ '--ipv4': '',
      \ '-k': '',
    \}

#### 5.2 Global Definitions

The global section is separated from the rest with two dashes `--` and may
include a default host, optional default cUrl options (buffer scope) and
optional default headers. These values are always included in each request.

Each request block has to start with either two dashes indicating it uses the
default host from the global section or any host only used by this block. If
a 'local host' is given, it's used instead of the one specified in the global
section. Additionally, a request block can specify extra cUrl options and
headers. Local headers are merged with and overwrite global headers.

    # Global definitions.
    // Default host.
    https://domain[:port]/...

    // Default (buffer scope) cUrl options.
    -L
    --connect-timeout 10

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

    // Local cUrl opts.
    -k
    --ipv4
    // This cUrl option overwrites the one in the global section.
    --connect-timeout 30
    -b /path/to/cookie
    -c /path/to/cookie

    // Extra headers.
    Xtra-Header: Some Extra.
    // This header will overwrite the one in the global section.
    X-Header: New Data

    POST /service
    var1=value

#### 5.3 Global Variable Declaration

VRC now supports variable declarations in the global scope. These variables
then can be used in the query paths. Notice: values are not url-encoded.

    # Global scope.
    http://host

    // Variable declarations (value passed as is).
    city = Some%20City
    zip = 12345
    --
    # End global scope.

    --
    GET /city/:city

    --
    GET /city/:city/zip/:zip

#### 5.4 Line-by-line Request Body

Since version 2.3.0, the request body can be specified on a line-by-line
basis. It's useful for name-value pair services. Each line of the request
body is passed to cURL using `--data` or `--data-urlencode` depending on
the verb.

To enable,

    let g:vrc_split_request_body = 1

or

    let b:vrc_split_request_body = 1

Then the request body can be specified as

    #
    # The following params in the request body will be
    # sent using `--data-urlencode`
    #
    http://localhost
    Content-Type: text/html; charset=UTF-8
    GET /service
    var1=value1
    var2=value2

This option won't take effect for `GET` request if the option
`vrc_allow_get_request_body` is set.

#### 5.4 Consecutive Request Verbs

A request block may have consecutive request verbs. The output of each request
verb is appended to the output view.

    http://localhost:9200
    PUT /test
    GET /test
    DELETE /test

### 6. Configuration

https://github.com/diepm/vim-rest-console/blob/master/doc/vim-rest-console.txt

### 7. Tips 'n Tricks

#### 7.1 POST Data in Bulk

Since v3.0, VRC supports POSTing data in bulk using in-line data or an
external data file. It's helpful for such APIs as Elasticsearch's Bulk API.

To use in-line data, first enable the Elasticsearch support flag.

    let g:vrc_elasticsearch_support = 1

The request would look like this.

    http://localhost:9200
    POST /testindex/_bulk
    { "index": { "_index": "test", "_type": "product" } }
    { "sku": "SKU1", "name": "Product name 1" }
    { "index": { "_index": "test", "_type": "product" } }
    { "sku": "SKU2", "name": "Product name 2" }

Using external data files doesn't need the support flag.

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

Thanks to the contributors (in alphabetical order of GitHub account)

    @dan-silva
    @dflupu
    @iamFIREcracker
    @jojoyuji
    @korin
    @minhajuddin
    @mjakl
    @nathanaelkane
    @p1otr
    @rawaludin
    @rlisowski
    @sethtrain
    @shanesmith
    @tdroxler
    @tonyskn
    @torbjornvatn

### 9. License

MIT
