local TriggerContext = require('complete.core.TriggerContext')
local FloatingWindow = require('complete.kit.Vim.FloatingWindow')

local idx = 0

---@class complete.ext.DefaultView
---@field private _service complete.core.CompletionService
---@field private _window complete.kit.Vim.Window
local DefaultView = {}
DefaultView.__index = DefaultView

---Create DefaultView
---@param service complete.core.CompletionService
---@return complete.ext.DefaultView
function DefaultView.new(service)
  local self = setmetatable({
    _service = service,
    _window = FloatingWindow.new()
  }, DefaultView)
  service:on_update(function(payload) self:update(payload) end)
  return self
end

function DefaultView:attach(bufnr)
  local id = ('complete.ext.DefaultView.%s'):format(idx)
  vim.on_key(function(_, typed)
    if bufnr ~= vim.api.nvim_get_current_buf() then
      return
    end
    local mode = vim.api.nvim_get_mode().mode
    if mode == 'i' and typed then
      vim.schedule(function()
        if mode == vim.api.nvim_get_mode().mode then
          self._service:complete(TriggerContext.create({
            trigger_character = typed
          }))
        end
    end)
    end
  end, vim.api.nvim_create_namespace(id))

  local group = vim.api.nvim_create_augroup(id, {
    clear = true
  })
  vim.api.nvim_create_autocmd({ 'InsertLeave' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      self._service:clear()
      self._window:hide()
    end
  })
end

---@param payload complete.core.CompletionService.OnUpdate.Payload
function DefaultView:update(payload)
  local padding = (' '):rep(1)
  local max_width = 0
  local lines = {}
  for _, match in ipairs(payload.matches) do
    table.insert(lines, ('%s%s%s'):format(padding, match.item:get_label(), padding))
    max_width = math.max(max_width, #match.item:get_label())
  end

  if #lines == 0 then
    if not self._service:is_completing() then
      self._window:hide()
    end
    return
  end

  vim.api.nvim_buf_set_lines(self._window:get_bufnr(), 0, -1, false, lines)

  local cur = vim.api.nvim_win_get_cursor(0)
  local pos = vim.fn.screenpos(0, cur[1], cur[2] + 1)
  self._window:show({
    width = max_width + #padding * 2,
    height = math.min(#lines, 8),
    row = pos.row,
    col = pos.curscol - 1 - #padding,
    anchor = 'NW',
    style = 'minimal',
    winhighlight = 'Normal:NormalFloat'
  })
end

return DefaultView
