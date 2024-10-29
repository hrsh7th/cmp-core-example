---@class complete.kit.Vim.Window.Config
---@field public row integer 0-indexed utf-8
---@field public col integer 0-indexed utf-8
---@field public width integer
---@field public height integer
---@field public anchor? "NW" | "NE" | "SW" | "SE"
---@field public style? string

---@class complete.kit.Vim.Window
---@field private _buf_option { [string]: any }
---@field private _win_option { [string]: any }
---@field private _buf integer
---@field private _win? integer
local FloatingWindow = {}
FloatingWindow.__index = FloatingWindow

---Create window.
---@return complete.kit.Vim.Window
function FloatingWindow.new()
  return setmetatable({
    _win_option = {},
    _buf_option = {},
    _buf = vim.api.nvim_create_buf(false, true),
  }, FloatingWindow)
end

---Set window option.
---@param key string
---@param value any
function FloatingWindow:set_win_option(key, value)
  self._win_option[key] = value
  self:_update_option()
end

---Set buffer option.
---@param key string
---@param value any
function FloatingWindow:set_buf_option(key, value)
  self._buf_option[key] = value
  self:_update_option()
end

---Returns the related bufnr.
function FloatingWindow:get_buf()
  return self._buf
end

---Returns the current win.
function FloatingWindow:get_win()
  return self._win
end

---Show the window
---@param config complete.kit.Vim.Window.Config
function FloatingWindow:show(config)
  if self:is_visible() then
    vim.api.nvim_win_set_config(self._win, {
      relative = 'editor',
      width = config.width,
      height = config.height,
      row = config.row,
      col = config.col,
      anchor = config.anchor,
      style = config.style,
    })
  else
    self._win = vim.api.nvim_open_win(self._buf, false, {
      relative = 'editor',
      width = config.width,
      height = config.height,
      row = config.row,
      col = config.col,
      anchor = config.anchor,
      style = config.style,
    })
  end
  self:_update_option()
end

---Hide the window
function FloatingWindow:hide()
  if self:is_visible() then
    vim.api.nvim_win_hide(self._win)
  end
end

---Returns true if the window is visible
function FloatingWindow:is_visible()
  if not self._win then
    return false
  end
  if not vim.api.nvim_win_is_valid(self._win) then
    return false
  end
  return true
end

---Update options.
function FloatingWindow:_update_option()
  for k, v in pairs(self._buf_option) do
    if vim.api.nvim_get_option_value(k, { buf = self._buf }) ~= v then
      vim.api.nvim_set_option_value(k, v, { buf = self._buf })
    end
  end
  if self:is_visible() then
    for k, v in pairs(self._win_option) do
      if vim.api.nvim_get_option_value(k, { win = self._win }) ~= v then
        vim.api.nvim_set_option_value(k, v, { win = self._win })
      end
    end
  end
end

return FloatingWindow
