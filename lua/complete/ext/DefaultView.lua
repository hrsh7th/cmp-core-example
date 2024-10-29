local Async = require('complete.kit.Async')
local LinePatch = require('complete.core.LinePatch')
local TriggerContext = require('complete.core.TriggerContext')
local FloatingWindow = require('complete.kit.Vim.FloatingWindow')

---@class complete.ext.DefaultView.Selection
---@field public index number
---@field public active boolean
---@field public before_text string

---@class complete.ext.DefaultView
---@field private _service complete.core.CompletionService
---@field private _window complete.kit.Vim.Window
---@field private _matches complete.core.Match[]
---@field private _selection? complete.ext.DefaultView.Selection
local DefaultView = {}
DefaultView.__index = DefaultView

---Create DefaultView
---@param service complete.core.CompletionService
---@return complete.ext.DefaultView
function DefaultView.new(service)
  local self = setmetatable({
    _service = service,
    _window = FloatingWindow.new(),
    _matches = {},
    _selection = nil,
  }, DefaultView)
  self._service:on_update(function(payload)
    self:render(payload)
  end)
  self._window:set_buf_option('buftype', 'nofile')
  self._window:set_win_option('conceallevel', 2)
  self._window:set_win_option('concealcursor', 'n')
  self._window:set_win_option('foldenable', false)
  self._window:set_win_option('wrap', false)
  self._window:set_win_option('winhighlight', 'Normal:NormalFloat,CursorLine:Visual')
  return self
end

function DefaultView:attach(bufnr)
  local id = ('complete.ext.DefaultView.%s'):format(vim.uv.now())
  local group = vim.api.nvim_create_augroup(id, { clear = true })
  local namespace = vim.api.nvim_create_namespace(id)

  -- trigger event.
  vim.on_key(function(_, typed)
    if bufnr ~= vim.api.nvim_get_current_buf() then
      return
    end
    if not typed or typed == '' then
      return
    end

    local mode = vim.api.nvim_get_mode().mode
    if mode == 'i' then
      vim.schedule(function()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local before_char = vim.api.nvim_get_current_line():sub(cursor[2], cursor[2])
        if before_char ~= typed then
          return
        end
        if mode ~= vim.api.nvim_get_mode().mode then
          self._service:update(TriggerContext.create())
          return
        end

        self._service:complete(TriggerContext.create({
          trigger_character = typed,
        }))
      end)
    end
  end, namespace)

  -- clear event.
  vim.api.nvim_create_autocmd({ 'InsertLeave' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      self._service:clear()
      self._window:hide()
      self._selection = nil
    end,
  })
end

---Return match at index.
---@param index number
---@return complete.core.Match?
function DefaultView:get_match_at(index)
  return self._matches[index]
end

---Return current selection.
---@return complete.ext.DefaultView.Selection?
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
  self._selection = nil
  self._matches = payload.matches

  -- hide window if no matches.
  if #payload.matches == 0 then
    if not self._service:is_completing() then
      self._window:hide()
    end
    return
  end

  -- draw lines.
  local padding = (' '):rep(1)
  local max_width = 0
  local lines = {}
  for _, match in ipairs(self._matches) do
    table.insert(lines, ('%s%s%s'):format(padding, match.item:get_label(), padding))
    max_width = math.max(max_width, #match.item:get_label())
  end
  vim.api.nvim_buf_set_lines(self._window:get_buf(), 0, -1, false, lines)

  -- show wndow.
  local cur = vim.api.nvim_win_get_cursor(0)
  local pos = vim.fn.screenpos(0, cur[1], cur[2] + 1)
  self._window:show({
    row = pos.row,
    col = pos.curscol - 1 - #padding,
    width = max_width + #padding * 2,
    height = math.min(#lines, 8),
    anchor = 'NW',
    style = 'minimal',
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
  local active = not preselect

  -- update selection.
  index = index % (vim.api.nvim_buf_line_count(self._window:get_buf()) + 1)
  if self._selection then
    self._selection.index = index
    self._selection.active = active
  else
    self._selection = {
      index = index,
      active = active,
      before_text = vim.api.nvim_get_current_line():sub(1, vim.api.nvim_win_get_cursor(0)[2]),
    }
  end

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
    return self:_insert_selection()
  end
end

---@return complete.kit.Async.AsyncTask
function DefaultView:_insert_selection()
  local cursor = vim.api.nvim_win_get_cursor(0)
  cursor[1] = cursor[1] - 1

  -- restore before text.
  vim.api.nvim_buf_set_text(0, cursor[1], 0, cursor[1], cursor[2], { self._selection.before_text })
  vim.api.nvim_win_set_cursor(0, { cursor[1] + 1, #self._selection.before_text })

  -- insert text.
  if self._selection.index ~= 0 then
    local item = self._matches[self._selection.index].item
    return LinePatch.apply_by_keys(0, cursor[2] - (item:get_offset() - 1), 0, item:get_select_text())
  end
  return Async.resolve()
end

return DefaultView
