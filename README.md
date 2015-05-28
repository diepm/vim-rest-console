# Vim REST Console (VRC)

### 1. Introduction

**VRC** is a Vim plug-in to help send requests to and display responses from
RESTful services in Vim. It's useful for working with REST services that use
JSON to exchange information between server and client such as ElasticSearch.

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
contains a *host*, *query*, and an *optional request body* (usually used by
POST). A block is defined as follows.

    # host
    http[s]://domain[:port]

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
    POST /index/type?pretty
    {
        "key": "a key",
        "value": "a value"
    }

    # Submitting a form.
    https://example.net:8080
    POST /form
    var1=value of var1
    &var2=value of var2

When the trigger key is called (`<C-j>` by default), VRC processes the request
block that the cursor stays within. The response is displayed in a new
vertically split buffer. This output buffer is reused if it's already present.

By default, the display/output buffer is named `__REST_response__`. If there
are multiple VRC buffers, they all share the same display buffer. To have a
separate display buffer for each VRC buffer, `b:vrc_output_buffer_name` can be
set in the buffer scope.

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

#### `vrc_nl_sep_post_data_patterns`

The *optional request body* usually spans multiple lines. VRC has to combine
them before passing to cURL. By default, VRC uses the empty string as the
separator; however, some services such as ElasticSearch need the newline
characters (`\n`) for some queries (e.g., `_bulk`).

This option is a list of patterns to tell VRC to join the optional request
body using the newline character when the query path

    GET /path/to/resource

matches any pattern in the list.

This option defaults to `['\v\W?_bulk\W?']`. To add new patterns,

    let g:vrc_nl_sep_post_data_patterns = [
    \    '\v\W?_bulk\W?',
    \    'OtherPattern',
    \]

#### `vrc_debug`

This option enables the debug mode by adding the `-v` option to the *curl*
command and also `echom` the command to the Vim console. It's turned off by
default.

### 7. TODOs

Currently, VRC combines the request body as a whole and passes it to cURL
using the `--data` or `--data_urlencode` option. It's useful for working with
JSON request body but not convenient for non-JSON data.

Need to improve the request body parsing so that for non-JSON request, it can
send each line of the data to cURL using a separate `--data` or
`--data-urlencode`.

### 8. License

MIT
