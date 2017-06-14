CHANGELOG
=========

* 3.0.2 (2017-06-13)

  * Fix shell escape BC with Vim 7.4.
  * Add CHANGELOG.
  * Update docs.

* 3.0.1 (2017-06-09)

  * Fix bug `-k` auto included.
  * Fix response content syntax-highlighting/formatting detection.

* 3.0.0 (2017-05-25)

  * Support raw cUrl options.
  * Support in-line data for `_bulk` request of ElasticSearch.
  * Deprecate the following VRC options in favor of cUrl options:
    - `vrc_connect_timeout` for `--connect-timeout`
    - `vrc_cookie_jar` for `-b` and `-c`
    - `vrc_follow_redirects` for `-L`
    - `vrc_include_response_header` for `-i`
    - `vrc_max_time` for `--max-time`
    - `vrc_resolve_to_ipv4` for `--ipv4`
    - `vrc_ssl_secure` for `-k`
  * Source code reformatted and refactored.

* 2.6.0 (2017-01-30)

  * Support global variable declaration.
  * Support consecutive request verbs.
  * Bug fix: When `vrc_show_command` is set, the command is displayed in the
    quickfix window instead of the output view. This fixes the output
    formatting bug when the option is enabled.
  * Add option `vrc_response_default_content_type` to set the default content-
    type of the response.

* 2.5.0 (2016-05-05)

  * Set `commentstring` so that lines can be commented by commenters.
  * Fix Content-Type to default to `application/json`.
  * Add option `vrc_show_command` to display the cUrl command along with output.

* 2.4.0 (2016-04-11)

  * Support POST empty body.
  * Add option to horizontal-split the output buffer.
  * Option to transform `\uXXXX` instances to corresponding symbols.

* 2.3.0 (2016-03-24)

  * GET request can have request body.
  * Request body can be specified on a line-by-line basis.

* 2.2.0 (2016-02-08)

  * Add support for PATCH, OPTIONS, and TRACE.

* 2.1.1 (2016-01-30)

  * Incompatibility fix.

* 2.1.0 (2016-01-25)

  * Support default values specified in a global section.
  * Add options for connection and max timeout.

* 2.0.0 (2015-11-24)

  * Support POST data from external files.
  * Proper use of cURL commands for HTTP verbs.
  * Request body is sent based on HTTP verbs.
    - GET, HEAD, DELETE: as GET params.
    - POST, PUT: as POST params.
  * Remove awkward syntaxes.
    - Option `vrc_nl_sep_post_data_patterns` removed.
    - GET params can be specified in request body.

