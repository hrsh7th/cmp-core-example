local LSP = require('complete.kit.LSP')
local Async = require('complete.kit.Async')
local LinePatch = require('complete.core.LinePatch')
local TriggerContext = require('complete.core.TriggerContext')
local FloatingWindow = require('complete.kit.Vim.FloatingWindow')

local CompletionItemKindLookup = {}
for k, v in pairs(LSP.CompletionItemKind) do
  CompletionItemKindLookup[v] = k
end

---@class complete.ext.DefaultView.Selection
---@field public index number
---@field public active? boolean
---@field public before_text? string

---@class complete.ext.DefaultView
---@field private _ns_id integer
---@field private _augroup integer
---@field private _service complete.core.CompletionService
---@field private _window complete.kit.Vim.FloatingWindow
---@field private _matches complete.core.Match[]
---@field private _selection complete.ext.DefaultView.Selection
---@field private _selection_queue complete.kit.Async.AsyncTask
---@field private _selecting integer
local DefaultView = {}
DefaultView.__index = DefaultView

---Create DefaultView
---@param service complete.core.CompletionService
---@return complete.ext.DefaultView
function DefaultView.new(service)
  local self = setmetatable({
    _ns_id = vim.api.nvim_create_namespace(('complete.ext.DefaultView.%s'):format(vim.uv.now())),
    _augroup = vim.api.nvim_create_augroup(('complete.ext.DefaultView.%s'):format(vim.uv.now()), { clear = true }),
    _service = service,
    _window = FloatingWindow.new(),
    _matches = {},
    _selection = { index = 0 },
    _selection_queue = Async.resolve(),
    _selecting = 0,
  }, DefaultView)
  self._service:on_update(function(payload)
    self:render(payload)
  end)
  self._window:set_buf_option('buftype', 'nofile')
  self._window:set_buf_option('tabstop', 1)
  self._window:set_win_option('conceallevel', 2)
  self._window:set_win_option('concealcursor', 'n')
  self._window:set_win_option('foldenable', false)
  self._window:set_win_option('wrap', false)
  self._window:set_win_option('winhighlight', 'Normal:Normal,FloatBorder:FloatBorder,CursorLine:Visual,Search:None')
  self._window:set_win_option('winhighlight', 'EndOfBuffer:PmenuSbar,NormalFloat:PmenuSbar', 'scrollbar_track')
  self._window:set_win_option('winhighlight', 'EndOfBuffer:PmenuThumb,NormalFloat:PmenuThumb', 'scrollbar_thumb')
  return self
end

function DefaultView:attach(bufnr)
  -- trigger event.
  local char = nil
  vim.on_key(function(_, typed)
    if bufnr ~= vim.api.nvim_get_current_buf() then
      return
    end
    if not typed or typed == '' then
      return
    end

    local mode = vim.api.nvim_get_mode().mode
    if mode == 'i' then
      char = typed
    end
  end, self._ns_id)

  -- TextChanged.
  vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChangedP' }, {
    group = self._augroup,
    buffer = bufnr,
    callback = function()
      if not char then
        return
      end
      if self._selecting > 0 then
        return
      end
      self._service:complete(TriggerContext.create({ trigger_character = char }))
    end,
  })

  -- clear event.
  vim.api.nvim_create_autocmd({ 'InsertLeave' }, {
    group = self._augroup,
    buffer = bufnr,
    callback = function()
      self._service:clear()
      self._window:hide()
      self._selection = { index = 0 }
    end,
  })
end

---Return true if window is visible.
---@return boolean
function DefaultView:is_visible()
  return self._window:is_visible()
end

---Return match at index.
---@param index number
---@return complete.core.Match?
function DefaultView:get_match_at(index)
  return self._matches[index]
end

---Return current selection.
---@return complete.ext.DefaultView.Selection
function DefaultView:get_selection()
  return self._selection
end

---@param index number
function DefaultView:select(index)
  return self:_update_selection(index, false)
end

---@param index number
function DefaultView:preselect(index)
  return self:_update_selection(index, true)
end

---@param payload complete.core.CompletionService.OnUpdate.Payload
function DefaultView:render(payload)
  if self._service:is_completing() then
    return
  end

  self._selection = { index = 0 }
  self._matches = payload.matches

  -- hide window if no matches.
  if #payload.matches == 0 then
    self._window:hide()
    return
  end

  -- icon resolver.
  local ok, MiniIcons = pcall(require, 'mini.icons')

  ---@param completion_item_kind complete.kit.LSP.CompletionItemKind
  local icon_resolver = function(completion_item_kind)
    if not ok then
      return ''
    end
    return MiniIcons.get('lsp', CompletionItemKindLookup[completion_item_kind]:lower())
  end

  -- compute columns.
  local padding = (' '):rep(1)
  local columns = {
    label = {
      max_width = 0,
      items = {},
    },
    kind = {
      max_width = 0,
      items = {},
    },
    detail = {
      max_width = 0,
      items = {},
    },
    description = {
      max_width = 0,
      items = {},
    }
  } --[[@type table<'label' | 'kind' | 'detail' | 'description', { max_width: integer, items: { width: integer, text: string }[] }>]]
  vim.api.nvim_buf_call(self._window:get_buf(), function()
    for _, match in ipairs(self._matches) do
      local label_text = match.item:get_label_text()
      local label_width = vim.fn.strdisplaywidth(label_text)
      columns.label.max_width = math.max(columns.label.max_width, label_width)
      table.insert(columns.label.items, {
        width = label_width,
        text = label_text
      })

      local kind_text = icon_resolver(match.item:get_kind())
      local kind_width = vim.fn.strdisplaywidth(kind_text)
      columns.kind.max_width = math.max(columns.kind.max_width, kind_width)
      table.insert(columns.kind.items, {
        width = kind_width,
        text = kind_text
      })

      local label_details = match.item:get_label_details()
      local detail_text = label_details.detail or ''
      local detail_width = vim.fn.strdisplaywidth(detail_text)
      columns.detail.max_width = math.max(columns.detail.max_width, detail_width)
      table.insert(columns.detail.items, {
        width = detail_width,
        text = detail_text
      })

      local description_text = label_details.description or ''
      local description_width = vim.fn.strdisplaywidth(description_text)
      columns.description.max_width = math.max(columns.description.max_width, description_width)
      table.insert(columns.description.items, {
        width = description_width,
        text = description_text
      })
    end
  end)

  -- draw lines.
  local offset = math.huge
  local lines = {}
  for i, match in ipairs(self._matches) do
    local label_item = columns.label.items[i]
    local kind_item = columns.kind.items[i]
    local detail_item = columns.detail.items[i]
    local description_item = columns.description.items[i]

    local line = ('%s%s%s%s%s%s%s%s%s%s'):format(
      padding,
      label_item.text,
      (' '):rep(columns.label.max_width - label_item.width + 1),
      kind_item.text,
      (' '):rep(columns.kind.max_width > 0 and (columns.kind.max_width - kind_item.width + 1) or 0),
      (' '):rep(columns.detail.max_width > 0 and (columns.detail.max_width - detail_item.width + 1) or 0),
      detail_item.text,
      (' '):rep(columns.description.max_width > 0 and (columns.description.max_width - description_item.width + 1) or 0),
      description_item.text,
      padding
    )
    table.insert(lines, line)
    offset = math.min(offset, match.item:get_offset())
  end
  vim.api.nvim_buf_set_lines(self._window:get_buf(), 0, -1, false, lines)

  -- decorate lines.
  for i, match in ipairs(self._matches) do
    -- label.
    for _, position in ipairs(match.match_positions) do
      vim.api.nvim_buf_set_extmark(self._window:get_buf(), self._ns_id, i - 1, position.start_index, {
        end_row = i - 1,
        end_col = position.end_index + 1,
        hl_group = position.hl_group or 'CmpItemAbbrMatch',
        hl_mode = 'combine',
      })
    end

    -- kind.
    local kind_item = columns.kind.items[i]
    if kind_item.text ~= '' then
      local kind_hl_group = ('CmpItemKind%s'):format(CompletionItemKindLookup[match.item:get_kind()])
      vim.api.nvim_buf_set_extmark(self._window:get_buf(), self._ns_id, i - 1, columns.label.max_width + 1, {
        end_row = i - 1,
        end_col = columns.label.max_width + #kind_item.text + 1,
        hl_group = kind_hl_group,
        hl_mode = 'combine',
      })
    end
  end

  -- show wndow.
  local max_width = #padding
  for _, column in pairs(columns) do
    if column.max_width > 0 then
      max_width = max_width + 1
    end
    max_width = max_width + column.max_width
  end
  max_width = max_width + #padding

  local cur = vim.api.nvim_win_get_cursor(0)
  local pos = vim.fn.screenpos(0, cur[1], offset)
  self._window:show({
    row = pos.row,
    col = pos.curscol - 1 - #padding,
    width = max_width,
    height = math.min(#lines, 8),
    anchor = 'NW',
    style = 'minimal',
    border = 'rounded',
  })

  if payload.preselect then
    self:preselect(payload.preselect)
  else
    self:select(0)
  end
end

---@param index number
---@param preselect boolean
function DefaultView:_update_selection(index, preselect)
  self._selecting = self._selecting + 1

  return Async.run(function()
    local active = not preselect

    -- update selection.
    index = index % (vim.api.nvim_buf_line_count(self._window:get_buf()) + 1)
    if self._selection.index == 0 then
      self._selection.before_text = vim.api.nvim_get_current_line():sub(1, vim.api.nvim_win_get_cursor(0)[2])
    end
    self._selection.index = index
    self._selection.active = active

    -- apply selection.
    if self._selection.index == 0 then
      self._window:set_win_option('cursorline', false)
      vim.api.nvim_win_set_cursor(self._window:get_win(), { 1, 0 })
    else
      self._window:set_win_option('cursorline', true)
      vim.api.nvim_win_set_cursor(self._window:get_win(), { self._selection.index, 0 })
    end

    -- insert text.
    if self._selection.active then
      self:_insert_selection():await()
    end

    -- resolve item.
    local match = self._matches[self._selection.index]
    if match then
      match.item:resolve()
    end

    Async.schedule():await()
    self._selecting = self._selecting - 1
  end)
end

---@return complete.kit.Async.AsyncTask
function DefaultView:_insert_selection()
  self._selection_queue = self._selection_queue:next(function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    cursor[1] = cursor[1] - 1

    -- restore before text.
    vim.api.nvim_buf_set_text(0, cursor[1], 0, cursor[1], cursor[2], { self._selection.before_text })
    vim.api.nvim_win_set_cursor(0, { cursor[1] + 1, #self._selection.before_text })

    -- insert text.
    if self._selection.index ~= 0 then
      local match = self._matches[self._selection.index]
      if match then
        return LinePatch.apply_by_keys(0, #self._selection.before_text - (match.item:get_offset() - 1), 0, match.item:get_select_text())
      end
    end
    return Async.resolve()
  end)
  return self._selection_queue
end

return DefaultView
