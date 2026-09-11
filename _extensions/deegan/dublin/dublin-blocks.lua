--[[
  dublin-blocks.lua

  Everything in the theme is reachable from ordinary markdown -- fenced divs,
  lists and links -- so a deck can be written and edited in Quarto's visual
  editor without dropping into LaTeX.

  Two rules cover almost all of it:

    * a box is a div, and every box takes an optional title=
        ::: {.takeaway title="What this changes"}
    * a thing made of several parts is a div wrapping a list
        ::: {.stats}      ::: {.contributions}      ::: {.nav}

  Cover settings come from the front matter rather than from header-includes:

    ---
    cover-photo: dublin.jpg
    cover-badge: Job Market Paper
    ---

  Without this filter pandoc silently discards the divs and prints their
  bodies as loose text, so the filter must travel with the .qmd.
--]]

-- ---------------------------------------------------------------- helpers

local function raw(s)
  return pandoc.RawBlock('latex', s)
end

local function warn(msg)
  io.stderr:write('[dublin] ' .. msg .. '\n')
end

local function inline_latex(inlines)
  return (pandoc.write(pandoc.Pandoc({ pandoc.Plain(inlines) }), 'latex')
            :gsub('%s+$', ''))
end

local function block_latex(blocks)
  return (pandoc.write(pandoc.Pandoc(blocks), 'latex'):gsub('%s+$', ''))
end

local function has_class(el, name)
  for _, c in ipairs(el.classes or {}) do
    if c == name then return true end
  end
  return false
end

-- title="..." is the documented spelling; the rest are tolerated so that a
-- reasonable guess works instead of failing silently.
local function title_of(el)
  local t = el.attributes['title']
       or el.attributes['name']
       or el.attributes['heading']
       or el.attributes['data-latex']
       or ''
  return (t:gsub('^{(.*)}$', '%1'))
end

local function attr_of(el, ...)
  for _, key in ipairs({ ... }) do
    if el.attributes[key] then return el.attributes[key] end
  end
  return ''
end

-- The first list inside a div, whichever kind it is.
local function first_list(el)
  for _, blk in ipairs(el.content) do
    if blk.t == 'BulletList' or blk.t == 'OrderedList' then
      return blk.content
    end
  end
  return nil
end

-- Split a list item into a bold lead-in and the remainder, so
--     - **0.22pp** lower annual income growth
-- becomes ('0.22pp', 'lower annual income growth').
local function split_lead(blocks)
  if #blocks == 0 then return nil, '' end
  local first = blocks[1]
  if first.t ~= 'Para' and first.t ~= 'Plain' then
    return nil, block_latex(blocks)
  end
  local ils = first.content
  if #ils == 0 or ils[1].t ~= 'Strong' then
    return nil, block_latex(blocks)
  end
  local lead = inline_latex(ils[1].content)
  local rest_ils = {}
  for i = 2, #ils do rest_ils[#rest_ils + 1] = ils[i] end
  while #rest_ils > 0 and rest_ils[1].t == 'Space' do
    table.remove(rest_ils, 1)
  end
  local rest = { pandoc.Para(rest_ils) }
  for i = 2, #blocks do rest[#rest + 1] = blocks[i] end
  return lead, block_latex(rest)
end

-- ------------------------------------------------------------ callout boxes
-- Every box takes an optional title. Aliases exist so the obvious word works.

local BOXES = {
  takeaway   = 'takeaway',   key        = 'takeaway',
  result     = 'result',     finding    = 'result',
  caveat     = 'caveat',     limitation = 'caveat',
  defn       = 'defn',       definition = 'defn',
  worked     = 'worked',     example    = 'worked',
  takeawaytitled = 'takeaway',   -- older spelling, still honoured
}

local function callout(el, env)
  local title = title_of(el)
  local open = (title ~= '')
    and ('\\begin{' .. env .. '}[' .. title .. ']')
    or  ('\\begin{' .. env .. '}')
  local blocks = el.content
  table.insert(blocks, 1, raw(open))
  table.insert(blocks, raw('\\end{' .. env .. '}'))
  return blocks
end

-- ------------------------------------------------------- headline numbers
--   ::: {.stats}
--   - **0.22pp** lower annual income growth
--   :::

local function stats(el)
  local list = first_list(el)
  if not list then
    warn('.stats needs a bullet list, each item starting **bold**')
    return nil
  end

  local items = {}
  for _, item in ipairs(list) do
    local value, label = split_lead(item)
    if not value then
      warn('.stats item has no bold value: ' .. label:sub(1, 40))
    else
      items[#items + 1] = { value = value, label = label }
    end
  end
  if #items == 0 then return nil end

  if #items == 1 then
    return { raw('\\statline{' .. items[1].value .. '}{'
                 .. items[1].label .. '}') }
  end
  if #items > 3 then
    warn('.stats shows at most three numbers; ' .. (#items - 3)
         .. ' dropped. Four will not read from the back of a room.')
  end

  local parts, n = {}, math.min(#items, 3)
  for i = 1, n do
    parts[#parts + 1] = '{' .. items[i].value .. '}{' .. items[i].label .. '}'
  end
  local cmd = (n == 2) and '\\statrowii' or '\\statrow'
  return { raw(cmd .. table.concat(parts)) }
end

-- ------------------------------------------------------ numbered contributions
--   ::: {.contributions}
--   1. **Heading** Body text.
--   :::

local function contributions(el)
  local list = first_list(el)
  if not list then
    warn('.contributions needs a numbered list, each item starting **bold**')
    return nil
  end
  local out = {}
  for i, item in ipairs(list) do
    local heading, body = split_lead(item)
    if not heading then
      warn('.contributions item has no bold heading: ' .. body:sub(1, 40))
      heading, body = body, ''
    end
    out[#out + 1] = raw('\\contribution{' .. i .. '}{' .. heading
                        .. '}{' .. body .. '}')
  end
  return out
end

-- ------------------------------------------------------------ exhibit notes
--   ::: {.tablenotes}
--   Standard errors clustered by county in parentheses.
--   :::
-- .notes is left alone: pandoc maps that to beamer speaker notes.

local function tablenotes(el)
  return { raw('\\dgnotes{' .. block_latex(el.content) .. '}') }
end

-- --------------------------------------------------------------- nav pills
--   ::: {.nav}
--   - [Data construction](#data)
--   - [Robustness](#rob){.level2}
--   - [Back to estimates](#main){.back}
--   :::
-- Destinations are ordinary heading ids: ## Robustness {#rob}

-- The return is level 3, not a level of its own.
local LEVELS = {
  level1 = 1, expected = 1,
  level2 = 2, supporting = 2,
  level3 = 3, detail = 3, back = 3, ['return'] = 3,
}

local function pill_for(link)
  local level, cmd = 1, '\\jumpto'
  for _, c in ipairs(link.classes or {}) do
    local lv = LEVELS[c]
    if lv then
      level = lv
      if c == 'back' or c == 'return' then cmd = '\\backto' end
    end
  end
  if link.target:match('^%a+://') then
    warn('.nav links point at slides in this deck, not the web: '
         .. link.target)
  end
  local target = link.target:gsub('^#', '')
  return cmd .. '[' .. level .. ']{' .. target .. '}{'
         .. inline_latex(link.content) .. '}'
end

local function links_in(blocks, out)
  for _, blk in ipairs(blocks) do
    if blk.t == 'Para' or blk.t == 'Plain' then
      for _, il in ipairs(blk.content) do
        if il.t == 'Link' then out[#out + 1] = pill_for(il) end
      end
    end
  end
end

local function nav(el)
  local pills = {}
  local list = first_list(el)
  if list then
    for _, item in ipairs(list) do links_in(item, pills) end
  else
    links_in(el.content, pills)
  end
  if #pills == 0 then
    warn('.nav needs a list of links, e.g. - [Robustness](#rob){.level2}')
    return nil
  end
  return { raw('\\navrow{' .. table.concat(pills, '\n        ') .. '}') }
end

-- ------------------------------------------------- contents, closing, appendix

local function toc(el)
  return { raw('\\toccontent') }
end

local function thanks(el)
  local email = attr_of(el, 'email', 'mail')
  local site  = attr_of(el, 'site', 'url', 'web', 'website')
  if email == '' and site == '' then
    warn('.thanks takes email="..." and site="..."')
  end
  return { raw('\\thankscontent{' .. email .. '}{' .. site .. '}') }
end

local function appendix(el)
  return { raw('\\appendixcontent') }
end

-- ------------------------------------------------------------------ dispatch

local DIVS = {
  stats         = stats,
  contributions = contributions,
  tablenotes    = tablenotes,
  fignotes      = tablenotes,
  exhibitnotes  = tablenotes,
  nav           = nav,
  toc           = toc,
  outline       = toc,
  contents      = toc,
  thanks        = thanks,
  appendix      = appendix,
}

local function dispatch(el)
  for _, cls in ipairs(el.classes) do
    local env = BOXES[cls]
    if env then return callout(el, env) end
    local handler = DIVS[cls]
    if handler then return handler(el) end
  end
  return nil
end

function Div(el)
  -- .nonumber has to survive this traversal: the final pass below is what
  -- reads it, and unwrapping here would leave the equation looking ordinary
  -- and get it numbered after all.
  if has_class(el, 'unnumbered') or has_class(el, 'nonumber') then
    return nil
  end
  return dispatch(el)
end

-- ----------------------------------------------------------------- tables
-- A markdown table is rewritten into the same `dgtable` environment a
-- hand-written one uses, so both routes give the identical object: full text
-- width, rules edge to edge, bold black heads, house rule weights. Anything
-- dgtable cannot express -- merged cells, several header rows, several
-- bodies -- is left to pandoc rather than silently mangled.

local ALIGN = {
  AlignLeft = 'l', AlignRight = 'r', AlignCenter = 'c', AlignDefault = 'l',
}

local function cell_latex(cell)
  if cell.col_span ~= 1 or cell.row_span ~= 1 then return nil end
  return block_latex(cell.contents)
end

local function row_latex(row, wrap)
  local cells = {}
  for _, cell in ipairs(row.cells) do
    local body = cell_latex(cell)
    if body == nil then return nil end
    cells[#cells + 1] = wrap and (body ~= '' and wrap(body) or '') or body
  end
  return table.concat(cells, ' & ') .. ' \\\\'
end

local function thead(body)
  return '\\thead{' .. body .. '}'
end

function Table(tbl)
  if #tbl.bodies ~= 1 then return nil end
  local body = tbl.bodies[1]
  if #body.head > 0 then return nil end          -- intermediate head rows
  if #tbl.foot.rows > 0 then return nil end

  local spec = {}
  for _, cs in ipairs(tbl.colspecs) do
    spec[#spec + 1] = ALIGN[cs[1]] or 'l'
  end

  local lines = {}
  for _, row in ipairs(tbl.head.rows) do
    local line = row_latex(row, thead)
    if not line then
      warn('table has merged cells; left to pandoc rather than restyled')
      return nil
    end
    lines[#lines + 1] = line
  end
  if #lines > 0 then lines[#lines + 1] = '\\midrule' end

  for _, row in ipairs(body.body) do
    local line = row_latex(row)
    if not line then
      warn('table has merged cells; left to pandoc rather than restyled')
      return nil
    end
    lines[#lines + 1] = line
  end

  local out = {}
  local caption = tbl.caption and tbl.caption.long
  if caption and #caption > 0 then
    out[#out + 1] = raw('\\tabcaption{' .. block_latex(caption) .. '}')
  end
  out[#out + 1] = raw('\\begin{dgtable}{' .. table.concat(spec, ' ') .. '}\n'
                      .. table.concat(lines, '\n') .. '\n\\end{dgtable}')
  return out
end

-- ------------------------------------------------------------------ the cover
-- Front-matter keys instead of LaTeX in header-includes.

local COVER = {
  { 'cover-photo', 'coverphoto' },
  { 'cover-scrim', 'coverscrim' },
  { 'cover-badge', 'coverbadge' },
  { 'cover-logo',  'coverlogo'  },
  { 'qr-code',     'thanksqr'   },
  { 'qr',          'thanksqr'   },
  { 'short-title', 'shorttitle' },
}

function Meta(m)
  local lines, seen = {}, {}
  for _, pair in ipairs(COVER) do
    local key, macro = pair[1], pair[2]
    if m[key] and not seen[macro] then
      seen[macro] = true
      lines[#lines + 1] = '\\' .. macro .. '{'
                          .. pandoc.utils.stringify(m[key]) .. '}'
    end
  end
  if #lines == 0 then return nil end

  local hi = m['header-includes']
  if hi == nil then
    hi = pandoc.MetaList({})
  elseif hi.t ~= 'MetaList' then
    hi = pandoc.MetaList({ hi })
  end
  hi[#hi + 1] = pandoc.MetaBlocks({ raw(table.concat(lines, '\n')) })
  m['header-includes'] = hi
  return m
end

-- ---------------------------------------------------------- numbered equations
-- Pandoc emits display maths as \[ ... \], which beamer never numbers. Every
-- display equation becomes a numbered `equation` instead, so equations carry
-- a number the way tables and figures do. Opt out with ::: {.nonumber}.
--
-- Done in a final top-down pass rather than in a Blocks handler, because the
-- ordinary traversal reaches the inside of a div before the div itself and
-- would number the very equations the div means to exempt.

local function display_math_of(blk)
  if blk.t ~= 'Para' and blk.t ~= 'Plain' then return nil end
  local math
  for _, il in ipairs(blk.content) do
    if il.t == 'Math' and il.mathtype == 'DisplayMath' then
      if math then return nil end
      math = il
    elseif il.t ~= 'Space' and il.t ~= 'SoftBreak' then
      return nil
    end
  end
  return math
end

local number_blocks

number_blocks = function(blocks, numbering)
  local out = {}
  for _, blk in ipairs(blocks) do
    if blk.t == 'Div' then
      local exempt = has_class(blk, 'unnumbered') or has_class(blk, 'nonumber')
      local inner = number_blocks(blk.content, numbering and not exempt)
      if exempt then
        for _, b in ipairs(inner) do out[#out + 1] = b end
      else
        blk.content = inner
        out[#out + 1] = blk
      end
    elseif blk.t == 'BlockQuote' then
      blk.content = number_blocks(blk.content, numbering)
      out[#out + 1] = blk
    else
      local math = numbering and display_math_of(blk)
      if math then
        local body = math.text:gsub('^%s+', ''):gsub('%s+$', '')
        out[#out + 1] = raw('\\begin{equation}\n' .. body .. '\n\\end{equation}')
      else
        out[#out + 1] = blk
      end
    end
  end
  return out
end

function Pandoc(doc)
  doc.blocks = number_blocks(doc.blocks, true)
  return doc
end
