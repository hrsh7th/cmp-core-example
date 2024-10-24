---@class complete.kit.Vim.Window.Config
---@field public row integer 0-indexed utf-8
---@field public col integer 0-indexed utf-8
---@field public width integer
---@field public height integer
---@field public anchor? "NW" | "NE" | "SW" | "SE"
---@field public style? string
---@field public winhighlight? string

---@class complete.kit.Vim.Window
---@field private _bufnr integer
---@field private _winid? integer
local FloatingWindow = {}
FloatingWindow.__index = FloatingWindow

---Create window.
---@return complete.kit.Vim.Window
function FloatingWindow.new()
  return setmetatable({
    _bufnr = vim.api.nvim_create_buf(false, true)
  }, FloatingWindow)
end

---Returns the related bufnr.
function FloatingWindow:get_bufnr()
  return self._bufnr
end

---Show the window
---@param config complete.kit.Vim.Window.Config
function FloatingWindow:show(config)
  if self:is_visible() then
    vim.api.nvim_win_set_config(self._winid, {
      relative = "editor",
      width = config.width,
      height = config.height,
      row = config.row,
      col = config.col,
      anchor = config.anchor,
      style = config.style
    })
  else
    self._winid = vim.api.nvim_open_win(self._bufnr, false, {
      relative = "editor",
      width = config.width,
      height = config.height,
      row = config.row,
      col = config.col,
      anchor = config.anchor,
      style = config.style
    })
  end
  if config.winhighlight then
    if vim.api.nvim_get_option_value('winhighlight', { win = self._winid }) ~= config.winhighlight then
      vim.api.nvim_set_option_value('winhighlight', config.winhighlight, { win = self._winid })
    end
  end
end

---Hide the window
function FloatingWindow:hide()
  if self:is_visible() then
    vim.api.nvim_win_hide(self._winid)
  end
end

---Returns true if the window is visible
function FloatingWindow:is_visible()
  if not self._winid then
    return false
  end
  if not vim.api.nvim_win_is_valid(self._winid) then
    return false
  end
  return true
end

return FloatingWindow
