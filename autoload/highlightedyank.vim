" highlighted-yank: Make the yanked region apparent!
" FIXME: Highlight region is incorrect when an input ^V[count]l ranges
"        multiple lines.
let s:Schedule = vital#highlightedyank#new().import('Schedule')
                  \.augroup('highlightedyank-highlight')
let s:NULLPOS = [0, 0, 0, 0]
let s:NULLREGION = {
  \ 'wise': '', 'blockwidth': 0,
  \ 'head': copy(s:NULLPOS), 'tail': copy(s:NULLPOS),
  \ }
let s:MAXCOL = 2147483647
let s:ON = 1
let s:OFF = 0
let s:HIGROUP = 'HighlightedyankRegion'

let s:state = s:ON
let s:quenchtask = {}


function! highlightedyank#debounce() abort "{{{
  if s:state is s:OFF
    return
  endif

  let operator = v:event.operator
  let regtype = v:event.regtype
  let regcontents = v:event.regcontents
  if exists('s:timer')
    call timer_stop(s:timer)
  endif
  let marks = [line("'["), line("']"), col("'["), col("']")]
  let s:timer = timer_start(1, {-> s:highlight(operator, regtype, regcontents, marks)})
endfunction "}}}

function! s:highlight(operator, regtype, regcontents, marks) abort "{{{
  if a:marks !=#  [line("'["), line("']"), col("'["), col("']")]
    return
  endif
  if a:operator !=# 'y' || a:regtype ==# ''
    return
  endif

  let view = winsaveview()
  let region = s:derive_region(a:regtype, a:regcontents)
  let maxlinenumber = s:get('max_lines', 10000)
  if region.tail[1] - region.head[1] + 1 <= maxlinenumber
    let hi_duration = s:get('highlight_duration', 1000)
    let timeout = s:get('timeout', 1000)
    let highlight = highlightedyank#highlight#new(region, timeout)
    if !highlight.empty() && hi_duration != 0
      call s:glow(highlight, s:HIGROUP, hi_duration)
    endif
  endif
  call winrestview(view)
endfunction "}}}
function! highlightedyank#on() abort "{{{
  let s:state = s:ON
endfunction "}}}
function! highlightedyank#off() abort "{{{
  let s:state = s:OFF
endfunction "}}}
function! highlightedyank#toggle() abort "{{{
  if s:state is s:ON
    call highlightedyank#off()
  else
    call highlightedyank#on()
  endif
endfunction "}}}
function! s:derive_region(regtype, regcontents) abort "{{{
  if a:regtype ==# 'v'
    let region = s:derive_region_char(a:regcontents)
  elseif a:regtype ==# 'V'
    let region = s:derive_region_line(a:regcontents)
  elseif a:regtype[0] ==# "\<C-v>"
    " NOTE: the width from v:event.regtype is not correct if 'clipboard' is
    "       unnamed or unnamedplus in windows
    " let width = str2nr(a:regtype[1:])
    let curcol = col('.') - 1
    let width = max(map(copy(a:regcontents), 'strdisplaywidth(v:val, curcol)'))
    let region = s:derive_region_block(a:regcontents, width)
  else
    let region = deepcopy(s:NULLREGION)
  endif
  return region
endfunction "}}}
function! s:derive_region_char(regcontents) abort "{{{
  let len = len(a:regcontents)
  let region = {}
  let region.wise = 'char'
  let region.head = getpos("'[")
  let region.tail = copy(region.head)
  if len == 0
    let region = deepcopy(s:NULLREGION)
  elseif len == 1
    let region.tail[2] += strlen(a:regcontents[0]) - 1
  elseif len == 2 && empty(a:regcontents[1])
    let region.tail[2] += strlen(a:regcontents[0])
  else
    if empty(a:regcontents[-1])
      let region.tail[1] += len - 2
      let region.tail[2] = strlen(a:regcontents[-2])
    else
      let region.tail[1] += len - 1
      let region.tail[2] = strlen(a:regcontents[-1])
    endif
  endif
  return s:modify_region(region)
endfunction "}}}
function! s:derive_region_line(regcontents) abort "{{{
  let region = {}
  let region.wise = 'line'
  let region.head = getpos("'[")
  let region.tail = getpos("']")
  if region.tail[2] == s:MAXCOL
    let region.tail[2] = col([region.tail[1], '$'])
  endif
  return region
endfunction "}}}
function! s:derive_region_block(regcontents, width) abort "{{{
  let len = len(a:regcontents)
  if len == 0
    return deepcopy(s:NULLREGION)
  endif

  let curpos = getpos('.')
  let region = deepcopy(s:NULLREGION)
  let region.wise = 'block'
  let region.head = getpos("'[")
  call setpos('.', region.head)
  if len > 1
    execute printf('normal! %sj', len - 1)
  endif
  execute printf('normal! %s|', virtcol('.') + a:width - 1)
  let region.tail = getpos('.')
  let region.blockwidth = a:width
  if strdisplaywidth(getline('.')) < a:width
    let region.blockwidth = s:MAXCOL
  endif
  call setpos('.', curpos)
  return s:modify_region(region)
endfunction "}}}
function! s:modify_region(region) abort "{{{
  " for multibyte characters
  if a:region.tail[2] != col([a:region.tail[1], '$']) && a:region.tail[3] == 0
    let cursor = getpos('.')
    call setpos('.', a:region.tail)
    call search('\%(^\|.\)', 'bc')
    let a:region.tail = getpos('.')
    call setpos('.', cursor)
  endif
  return a:region
endfunction "}}}
function! s:glow(highlight, hi_group, duration) abort "{{{
  if !empty(s:quenchtask) && !s:quenchtask.hasdone()
    call s:quenchtask.trigger()
  endif
  if !a:highlight.show(a:hi_group)
    return
  endif

  let switchtask = s:Schedule.Task()
  call switchtask.repeat(-1)
  call switchtask.call(a:highlight.switch, [], a:highlight)
  call switchtask.waitfor(['BufEnter'])

  let s:quenchtask = s:Schedule.Task()
  call s:quenchtask.call(a:highlight.quench, [], a:highlight)
  call s:quenchtask.call(switchtask.cancel, [], switchtask)
  call s:quenchtask.waitfor([a:duration, ['TextChanged', '<buffer>'],
    \ ['InsertEnter', '<buffer>'], ['BufUnload', '<buffer>']])
endfunction "}}}
function! s:get(name, default) abort  "{{{
  let identifier = 'highlightedyank_' . a:name
  return get(b:, identifier, get(g:, identifier, a:default))
endfunction "}}}

" vim:set foldmethod=marker:
" vim:set commentstring="%s:
" vim:set ts=2 sts=2 sw=2:
