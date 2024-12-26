local LSP = require('complete.kit.LSP')
local Async = require('complete.kit.Async')
local Keymap = require('complete.kit.Vim.Keymap')
local Markdown = require('complete.core.Markdown')
local TriggerContext = require('complete.core.TriggerContext')
local FloatingWindow = require('complete.kit.Vim.FloatingWindow')

local CompletionItemKindLookup = {}
for k, v in pairs(LSP.CompletionItemKind) do
  CompletionItemKindLookup[v] = k
end

local padding_inline_border = { '', '', '', ' ', '', '', '', ' ' }

-- icon resolver.
local ok, MiniIcons = pcall(require, 'mini.icons')

---@param completion_item_kind complete.kit.LSP.CompletionItemKind
---@return string, string?
local icon_resolver = function(completion_item_kind)
  if not ok then
    return '', ''
  end
  return MiniIcons.get('lsp', (CompletionItemKindLookup[completion_item_kind] or 'text'):lower())
end

local config = {
  max_win_height = 18,
  padding_left = 1,
  padding_right = 1,
  gap = 1,
}

---@type { is_label?: boolean, padding_left: integer, padding_right: integer, align: 'left' | 'right', resolve: fun(item: complete.core.CompletionItem): { [1]: string, [2]?: string } }[]
local components = {
  {
    padding_left = 0,
    padding_right = 0,
    align = 'right',
    resolve = function(item)
      local kind = item:get_kind() or LSP.CompletionItemKind.Text
      return { icon_resolver(kind) }
    end,
  },
  {
    is_label = true,
    padding_left = 0,
    padding_right = 0,
    align = 'left',
    resolve = function(item)
      return {
        vim.fn.strcharpart(item:get_label_text(), 0, 48),
        'CmpItemAbbr',
      }
    end,
  },
  {
    padding_left = 0,
    padding_right = 0,
    align = 'right',
    resolve = function(item)
      return {
        vim.fn.strcharpart(item:get_label_details().description or '', 0, 28),
        'Comment',
      }
    end,
  },
}

---@class complete.ext.DefaultView
---@field private _ns_id integer
---@field private _option { border?: string }
---@field private _augroup integer
---@field private _service complete.core.CompletionService
---@field private _menu_window complete.kit.Vim.FloatingWindow
---@field private _docs_window complete.kit.Vim.FloatingWindow
---@field private _matches complete.core.Match[]
---@field private _selected_item? complete.core.CompletionItem
local DefaultView = {}
DefaultView.__index = DefaultView

---Create DefaultView
---@param service complete.core.CompletionService
---@param option? { border?: string }
---@return complete.ext.DefaultView
function DefaultView.new(service, option)
  local self = setmetatable({
    _ns_id = vim.api.nvim_create_namespace(('complete.ext.DefaultView.%s'):format(vim.uv.now())),
    _option = option or {},
    _augroup = vim.api.nvim_create_augroup(('complete.ext.DefaultView.%s'):format(vim.uv.now()), { clear = true }),
    _service = service,
    _menu_window = FloatingWindow.new(),
    _docs_window = FloatingWindow.new(),
    _queue = Async.resolve(),
    _matches = {},
  }, DefaultView)
  self._service:on_update(function(payload)
    self:_on_update(payload)
  end)
  self._service:on_select(function(payload)
    self:_on_select(payload)
  end)

  -- common window config.
  for _, win in ipairs({ self._menu_window, self._docs_window }) do
    win:set_buf_option('buftype', 'nofile')
    win:set_buf_option('tabstop', 1)
    win:set_buf_option('shiftwidth', 1)
    win:set_win_option('scrolloff', 0)
    win:set_win_option('conceallevel', 2)
    win:set_win_option('concealcursor', 'n')
    win:set_win_option('cursorlineopt', 'line')
    win:set_win_option('foldenable', false)
    win:set_win_option('wrap', false)
    if self._option.border then
      win:set_win_option('winhighlight',
        'NormalFloat:Normal,Normal:Normal,FloatBorder:Normal,CursorLine:Visual,Search:None')
    else
      win:set_win_option('winhighlight',
        'NormalFloat:Pmenu,Normal:Pmenu,FloatBorder:Pmenu,CursorLine:PmenuSel,Search:None')
    end
    win:set_win_option('winhighlight', 'NormalFloat:PmenuSbar,Normal:PmenuSbar,EndOfBuffer:PmenuSbar,Search:None',
      'scrollbar_track')
    win:set_win_option('winhighlight', 'NormalFloat:PmenuThumb,Normal:PmenuThumb,EndOfBuffer:PmenuThumb,Search:None',
      'scrollbar_thumb')
  end

  -- docs window config.
  self._docs_window:set_config({ markdown = true })
  self._docs_window:set_win_option('wrap', true)

  return self
end

function DefaultView:attach(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr

  -- TextChanged.
  vim.api.nvim_create_autocmd({ 'TextChangedI' }, {
    group = self._augroup,
    pattern = ('<buffer=%s>'):format(bufnr),
    callback = function()
      self._service:complete(TriggerContext.create())
    end,
  })

  -- CursorMovedI.
  vim.api.nvim_create_autocmd({ 'CursorMovedI' }, {
    group = self._augroup,
    pattern = ('<buffer=%s>'):format(bufnr),
    callback = function()
      vim.schedule(function()
        self._service:update()
      end)
    end,
  })

  -- clear event.
  vim.api.nvim_create_autocmd({ 'ModeChanged' }, {
    group = self._augroup,
    pattern = ('<buffer=%s>'):format(bufnr),
    callback = function(e)
      local prev = e.match:sub(1, 1)
      vim.schedule(function()
        local next = vim.api.nvim_get_mode().mode
        if prev == 's' and next == 'i' then
          self._service:complete(TriggerContext.create())
        elseif next ~= 'i' then
          self:close()
          self._service:clear()
        end
      end)
    end,
  })
end

---Return true if window is visible.
---@return boolean
function DefaultView:is_visible()
  return self._menu_window:is_visible()
end

---Close window.
---@return nil
function DefaultView:close()
  self._menu_window:hide()
  self._docs_window:hide()
end

---@param payload complete.core.CompletionService.OnUpdate.Payload
function DefaultView:_on_update(payload)
  -- hide window if no matches.
  self._matches = payload.matches
  if #self._matches == 0 then
    self:close()
    return
  end

  ---@type fun(text: string): integer
  local get_strwidth
  do
    local cache = {}
    get_strwidth = function(text)
      if not cache[text] then
        cache[text] = vim.api.nvim_strwidth(text)
      end
      return cache[text]
    end
  end

  -- init columns.
  ---@type { is_label?: boolean, byte_width: integer, padding_left: integer, padding_right: integer, align: 'left' | 'right', resolved: { [1]: string, [2]?: string }[] }[]
  local columns = {}
  for _, component in ipairs(components) do
    table.insert(columns, {
      is_label = component.is_label,
      byte_width = 0,
      padding_left = component.padding_left,
      padding_right = component.padding_right,
      align = component.align,
      resolved = {},
    })
  end

  -- compute columns.
  local min_offset = math.huge
  for i, match in ipairs(self._matches) do
    min_offset = math.min(min_offset, match.item:get_offset())
    for j, component in ipairs(components) do
      local resolved = component.resolve(match.item)
      columns[j].byte_width = math.max(columns[j].byte_width, #resolved[1])
      columns[j].resolved[i] = resolved
    end
  end

  -- remove empty columns.
  for i = #columns, 1, -1 do
    if columns[i].byte_width == 0 then
      table.remove(columns, i)
    end
  end

  -- set decoration provider.
  vim.api.nvim_set_decoration_provider(self._ns_id, {
    on_win = function(_, _, buf, toprow, botrow)
      if buf ~= self._menu_window:get_buf() then
        return
      end

      for row = toprow, botrow do
        local off = config.padding_left
        for _, column in ipairs(columns) do
          local resolved = column.resolved[row + 1]
          off = off + column.padding_left
          vim.api.nvim_buf_set_extmark(buf, self._ns_id, row, off, {
            end_row = row,
            end_col = off + column.byte_width,
            hl_group = resolved[2],
            hl_mode = 'combine',
            ephemeral = true,
          })
          if column.is_label then
            for _, pos in ipairs(self._matches[row + 1].match_positions) do
              vim.api.nvim_buf_set_extmark(buf, self._ns_id, row, off + pos.start_index - 1, {
                end_row = row,
                end_col = off + pos.end_index,
                hl_group = pos.hl_group or 'CmpItemAbbrMatch',
                hl_mode = 'combine',
                ephemeral = true,
              })
            end
          end
          off = off + column.byte_width + column.padding_right + config.gap
        end
      end
    end,
  })

  -- create formatting.
  local parts = {}
  table.insert(parts, (' '):rep(config.padding_left or 1))
  for i, column in ipairs(columns) do
    table.insert(parts, (' '):rep(column.padding_left or 0))
    table.insert(parts, '%s%s')
    table.insert(parts, (' '):rep(column.padding_right or 0))
    if i ~= #columns then
      table.insert(parts, (' '):rep(config.gap or 1))
    end
  end
  table.insert(parts, (' '):rep(config.padding_right or 1))
  local formatting = table.concat(parts, '')

  -- draw lines.
  local display_width = 0
  local lines = {}
  for i in ipairs(self._matches) do
    local args = {}
    for _, column in ipairs(columns) do
      local resolved = column.resolved[i]
      if column.align == 'right' then
        table.insert(args, (' '):rep(column.byte_width - #resolved[1]))
        table.insert(args, resolved[1])
      else
        table.insert(args, resolved[1])
        table.insert(args, (' '):rep(column.byte_width - #resolved[1]))
      end
    end
    local line = formatting:format(unpack(args))
    table.insert(lines, line)
    display_width = math.max(display_width, get_strwidth(line))
  end
  vim.api.nvim_buf_set_lines(self._menu_window:get_buf(), 0, -1, false, lines)

  -- show window.
  local leading_text = vim.api.nvim_get_current_line():sub(min_offset, vim.fn.col('.') - 1)
  local pos = vim.fn.screenpos(0, vim.fn.line('.'), vim.fn.col('.'))
  local row = pos.row - 1 -- default row should be below the cursor. so we use 1-origin as-is.
  local col = pos.col - vim.api.nvim_strwidth(leading_text)

  local border_size = FloatingWindow.get_border_size(self._option.border)
  local row_off = 1
  local col_off = -(border_size.left + config.padding_left) - 1 -- `-1` is first char align.
  local anchor = 'NW'

  local can_bottom = row + row_off + math.min(config.max_win_height, #self._matches) <= vim.o.lines
  if not can_bottom then
    anchor = 'SW'
    row_off = 0
  end

  self._menu_window:show({
    row = row + row_off,
    col = col + col_off,
    width = display_width,
    height = math.min(#lines, 8),
    anchor = anchor,
    style = 'minimal',
    border = self._option.border,
  })
  self._menu_window:set_win_option('cursorline', self._service:get_selection().index ~= 0)
end

---On select event.
---@param payload complete.core.CompletionService.OnSelect.Payload
function DefaultView:_on_select(payload)
  if not self._menu_window:is_visible() then
    return
  end
  local resume = self._service:prevent()
  return Async.run(function()
    -- apply selection.
    if payload.selection.index == 0 then
      self._menu_window:set_win_option('cursorline', false)
      vim.api.nvim_win_set_cursor(self._menu_window:get_win(), { 1, 0 })
    else
      self._menu_window:set_win_option('cursorline', true)
      vim.api.nvim_win_set_cursor(self._menu_window:get_win(), { payload.selection.index, 0 })
    end

    -- set selected_item.
    local prev_item = self._selected_item
    local match = payload.matches[payload.selection.index]
    self._selected_item = match and match.item

    -- insert text.
    if not payload.selection.preselect then
      self._insert_selection(payload.selection.text_before, self._selected_item, prev_item):await()
    end

    -- show documentation.
    self:_update_docs(self._selected_item)

    resume()
  end)
end

---Insert selection.
---@param text_before string
---@param item_next? complete.core.CompletionItem
---@param item_prev? complete.core.CompletionItem
---@return complete.kit.Async.AsyncTask
function DefaultView._insert_selection(text_before, item_next, item_prev)
  local text = vim.api.nvim_get_current_line()
  local cursor = vim.api.nvim_win_get_cursor(0)[2]

  local keys = {}

  -- remove inserted text to previous item.
  local to_remove_offset = item_prev and item_prev:get_offset() - 1 or #text_before
  if to_remove_offset < cursor then
    table.insert(keys,
      Keymap.termcodes('<C-g>U<Left><Del>'):rep(vim.fn.strchars(text:sub(to_remove_offset + 1, cursor), true)))
  end

  -- restore missing characters.
  if to_remove_offset < #text_before then
    table.insert(keys, text_before:sub(to_remove_offset + 1))
  end

  -- apply `select_text`.
  if item_next then
    local next_offset = item_next:get_offset() - 1
    if next_offset < #text_before then
      table.insert(keys,
        Keymap.termcodes('<C-g>U<Left><Del>'):rep(vim.fn.strchars(text_before:sub(next_offset + 1), true)))
    end
    table.insert(keys, item_next:get_select_text())
  end
  return Keymap.send(keys)
end

---Update documentation.
---@param item? complete.core.CompletionItem
function DefaultView:_update_docs(item)
  if not item then
    self._docs_window:hide()
    return
  end

  item:resolve():next(function()
    if item ~= self._selected_item then
      return
    end

    if not self._menu_window:is_visible() then
      self._docs_window:hide()
      return
    end

    local documentation = item:get_documentation()
    if not documentation then
      self._docs_window:hide()
      return
    end

    local menu_viewport = self._menu_window:get_viewport()
    local docs_border = menu_viewport.border and menu_viewport.border or padding_inline_border

    -- set buffer contents.
    Markdown.set(self._docs_window:get_buf(), self._ns_id, vim.split(documentation.value, '\n', { plain = true }))

    local max_width = math.floor(vim.o.columns * 0.5)
    local max_height = math.floor(vim.o.lines * 0.7)
    local border_size = FloatingWindow.get_border_size(docs_border)
    local content_size = FloatingWindow.get_content_size({
      bufnr = self._docs_window:get_buf(),
      wrap = self._docs_window:get_win_option('wrap'),
      max_inner_width = max_width - border_size.h,
      markdown = self._docs_window:get_config().markdown,
    })

    local restricted_size = FloatingWindow.compute_restricted_size({
      border_size = border_size,
      content_size = content_size,
      max_outer_width = max_width,
      max_outer_height = max_height,
    })

    local row = menu_viewport.row
    local col = menu_viewport.col + menu_viewport.outer_width
    self._docs_window:show({
      row = row, --[[@as integer]]
      col = col,
      width = restricted_size.inner_width,
      height = restricted_size.inner_height,
      border = docs_border,
      style = 'minimal',
    })
  end)
end

return DefaultView
