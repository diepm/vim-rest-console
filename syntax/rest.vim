if exists('b:current_syntax')
    finish
endif

syntax match restHost '\c\v^\s*HTTPS?\://\S+$'
highlight link restHost Label

syntax match restKeyword '\c\v^\s*(GET|POST|PUT|DELETE|HEAD)\s'
highlight link restKeyword Macro

syntax match restComment '\v^\s*(#|//).*$'
highlight link restComment Comment

let b:current_syntax = 'rest'
