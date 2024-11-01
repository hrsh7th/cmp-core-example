local kit = require('complete.kit')

---Analyze border size.
---@param border string | string[]
---@return { top: integer, right: integer, bottom: integer, left: integer }
local function analyze_border_size(border)
  if not border then
    return { top = 0, right = 0, bottom = 0, left = 0 }
  end
  if type(border) == 'string' then
    if border == 'none' then
      return { top = 0, right = 0, bottom = 0, left = 0 }
    elseif border == 'single' then
      return { top = 1, right = 1, bottom = 1, left = 1 }
    elseif border == 'double' then
      return { top = 2, right = 2, bottom = 2, left = 2 }
    elseif border == 'rounded' then
      return { top = 1, right = 1, bottom = 1, left = 1 }
    elseif border == 'solid' then
      return { top = 1, right = 1, bottom = 1, left = 1 }
    elseif border == 'shadow' then
      return { top = 0, right = 1, bottom = 1, left = 0 }
    end
    return { top = 0, right = 0, bottom = 0, left = 0 }
  end
  local chars = border --[=[@as string[]]=]
  while #chars < 8 do
    chars = kit.concat(chars, chars)
  end
  return {
    top = vim.fn.strdisplaywidth(chars[2]),
    right = vim.fn.strdisplaywidth(chars[4]),
    bottom = vim.fn.strdisplaywidth(chars[6]),
    left = vim.fn.strdisplaywidth(chars[8])
  }
end

---Returns true if the window is visible
---@param win? integer
---@return boolean
local function is_visible(win)
  if not win then
    return false
  end
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  return true
end

---Show the window
---@param win? integer
---@param buf integer
---@param config complete.kit.Vim.FloatingWindow.Config
---@return integer
local function show_or_move(win, buf, config)
  if is_visible(win) then
    vim.api.nvim_win_set_config(win --[=[@as integer]=], {
      relative = "editor",
      width = config.width,
      height = config.height,
      row = config.row,
      col = config.col,
      anchor = config.anchor,
      style = config.style,
      border = config.border,
      zindex = config.zindex,
    })
    return win --[=[@as integer]=]
  else
    return vim.api.nvim_open_win(buf, false, {
      noautocmd = true,
      relative = "editor",
      width = config.width,
      height = config.height,
      row = config.row,
      col = config.col,
      anchor = config.anchor,
      style = config.style,
      border = config.border,
      zindex = config.zindex,
    })
  end
end

---@class complete.kit.Vim.FloatingWindow.Config
---@field public row integer 0-indexed utf-8
---@field public col integer 0-indexed utf-8
---@field public width integer
---@field public height integer
---@field public border? string | string[]
---@field public anchor? "NW" | "NE" | "SW" | "SE"
---@field public style? string
---@field public zindex? integer

---@class complete.kit.Vim.FloatingWindow.Analyzed
---@field public content_width integer
---@field public content_height integer
---@field public outer_width integer
---@field public outer_height integer
---@field public border_size { top: integer, right: integer, bottom: integer, left: integer }
---@field public scrollbar boolean

---@class complete.kit.Vim.FloatingWindow
---@field private _augroup string
---@field private _buf_option table<string, { [string]: any }>
---@field private _win_option table<string, { [string]: any }>
---@field private _buf integer
---@field private _scrollbar_track_buf integer
---@field private _scrollbar_thumb_buf integer
---@field private _win? integer
---@field private _scrollbar_track_win? integer
---@field private _scrollbar_thumb_win? integer
local FloatingWindow = {}
FloatingWindow.__index = FloatingWindow

---Create window.
---@return complete.kit.Vim.FloatingWindow
function FloatingWindow.new()
  return setmetatable({
    _augroup = vim.api.nvim_create_augroup(('complete.kit.Vim.FloatingWindow:%s'):format(kit.unique_id()), {
      clear = true,
    }),
    _win_option = {},
    _buf_option = {},
    _buf = vim.api.nvim_create_buf(false, true),
    _scrollbar_track_buf = vim.api.nvim_create_buf(false, true),
    _scrollbar_thumb_buf = vim.api.nvim_create_buf(false, true),
  }, FloatingWindow)
end

---Set window option.
---@param key string
---@param value any
---@param kind? 'main' | 'scrollbar_track' | 'scrollbar_thumb'
function FloatingWindow:set_win_option(key, value, kind)
  kind = kind or 'main'
  self._win_option[kind] = self._win_option[kind] or {}
  self._win_option[kind][key] = value
  self:_update_option()
end

---Set buffer option.
---@param key string
---@param value any
---@param kind? 'main' | 'scrollbar_track' | 'scrollbar_thumb'
function FloatingWindow:set_buf_option(key, value, kind)
  kind = kind or 'main'
  self._buf_option[kind] = self._buf_option[kind] or {}
  self._buf_option[kind][key] = value
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
---@param config complete.kit.Vim.FloatingWindow.Config
function FloatingWindow:show(config)
  local analyzed = self:analyze({
    max_width = config.width,
    max_height = config.height,
    border = config.border
  })

  local zindex = config.zindex or 1000

  self._win = show_or_move(self._win, self._buf, {
    row = config.row,
    col = config.col,
    width = analyzed.outer_width,
    height = analyzed.outer_height,
    anchor = config.anchor,
    style = config.style,
    border = config.border,
    zindex = zindex,
  })

  vim.api.nvim_create_autocmd('WinScrolled', {
    group = self._augroup,
    callback = function(event)
      if tostring(event.match) == tostring(self._win) then
        self:_update_scrollbar()
      end
    end,
  })

  self:_update_scrollbar()
  self:_update_option()
end

---Hide the window
function FloatingWindow:hide()
  if is_visible(self._win) then
    vim.api.nvim_win_hide(self._win)
  end
  if is_visible(self._scrollbar_track_win) then
    vim.api.nvim_win_hide(self._scrollbar_track_win)
  end
  if is_visible(self._scrollbar_thumb_win) then
    vim.api.nvim_win_hide(self._scrollbar_thumb_win)
  end
end

---Scroll the window.
---@param delta integer
function FloatingWindow:scroll(delta)
  if not is_visible(self._win) then
    return
  end
  vim.api.nvim_win_call(self._win, function()
    local topline = vim.fn.getwininfo(self._win)[1].topline
    topline = topline + delta
    topline = math.max(topline, 1)
    topline = math.min(topline, vim.api.nvim_buf_line_count(self._buf) - vim.api.nvim_win_get_height(self._win) + 1)
    vim.api.nvim_command(('normal! %szt'):format(topline))
  end)
end

---Returns true if the window is visible
function FloatingWindow:is_visible()
  return is_visible(self._win)
end

---Analyze window layout.
---@param config { max_width: integer, max_height: integer, border: string | string[] }
---@return complete.kit.Vim.FloatingWindow.Analyzed
function FloatingWindow:analyze(config)
  local border_size = analyze_border_size(config.border)

  -- calculate content width.
  local content_width --[=[@as integer]=]
  do
    local max_text_width = 0
    for _, text in ipairs(vim.api.nvim_buf_get_lines(self._buf, 0, -1, false)) do
      max_text_width = math.max(max_text_width, vim.fn.strdisplaywidth(text))
    end
    content_width = max_text_width
  end

  -- calculate content height.
  local content_height --[=[@as integer]=]
  do
    if vim.o.wrap and self._win_option.wrap ~= false then
      -- `-1` means possible scollbar width.
      local possible_inner_width = config.max_width - border_size.left - border_size.right - 1
      local height = 0
      for _, text in ipairs(vim.api.nvim_buf_get_lines(self._buf, 0, -1, false)) do
        height = height + math.ceil(vim.fn.strdisplaywidth(text) / (possible_inner_width))
      end
      content_height = height
    else
      content_height = vim.api.nvim_buf_line_count(self._buf)
    end
  end

  local scrollbar = content_height > config.max_height
  local outer_width = math.min(content_width + border_size.left + border_size.right + (scrollbar and 1 or 0), config.max_width)
  local outer_height = math.min(content_height + border_size.top + border_size.bottom, config.max_height)
  return {
    content_width = content_width,
    content_height = content_height,
    outer_width = outer_width,
    outer_height = outer_height,
    border_size = border_size,
    scrollbar = scrollbar
  }
end

---Update scrollbar.
function FloatingWindow:_update_scrollbar()
  if not is_visible(self._win) then
    return
  end

  local win_width = vim.api.nvim_win_get_width(self._win)
  local win_height = vim.api.nvim_win_get_height(self._win)
  local win_pos = vim.api.nvim_win_get_position(self._win)
  local win_config = vim.api.nvim_win_get_config(self._win)

  local analyzed = self:analyze({
    max_width = win_width,
    max_height = win_height,
    border = win_config.border
  })
  if analyzed.scrollbar then
    do
      self._scrollbar_track_win = show_or_move(
        self._scrollbar_track_win,
        self._scrollbar_track_buf,
        {
          row = win_pos[1] + analyzed.border_size.top,
          col = win_pos[2] + analyzed.border_size.left + analyzed.border_size.right + win_width,
          width = 1,
          height = analyzed.outer_height,
          style = 'minimal',
          zindex = win_config.zindex + 1,
        }
      )
    end
    do
      local area_height = win_height
      local topline = vim.fn.getwininfo(self._win)[1].topline
      local thumb_height = math.ceil(area_height * (area_height / analyzed.content_height))
      local thumb_row = math.floor(area_height * (topline / analyzed.content_height))
      self._scrollbar_thumb_win = show_or_move(
        self._scrollbar_thumb_win,
        self._scrollbar_thumb_buf,
        {
          row = win_pos[1] + analyzed.border_size.top + thumb_row,
          col = win_pos[2] + analyzed.border_size.left + analyzed.border_size.right + win_width,
          width = 1,
          height = thumb_height,
          style = 'minimal',
          zindex = win_config.zindex + 2,
        }
      )
    end
  else
    if is_visible(self._scrollbar_track_win) then
      vim.api.nvim_win_hide(self._scrollbar_track_win)
    end
    if is_visible(self._scrollbar_thumb_win) then
      vim.api.nvim_win_hide(self._scrollbar_thumb_win)
    end
  end
end

---Update options.
function FloatingWindow:_update_option()
  -- update buf.
  for kind, buf in pairs({
    main = self._buf,
    scrollbar_track = self._scrollbar_track_buf,
    scrollbar_thumb = self._scrollbar_thumb_buf,
  }) do
    for k, v in pairs(self._buf_option[kind] or {}) do
      if vim.api.nvim_get_option_value(k, { buf = buf }) ~= v then
        vim.api.nvim_set_option_value(k, v, { buf = buf })
      end
    end
  end

  -- update win.
  for kind, win in pairs({
    main = self._win,
    scrollbar_track = self._scrollbar_track_win,
    scrollbar_thumb = self._scrollbar_thumb_win,
  }) do
    if is_visible(win) then
      for k, v in pairs(self._win_option[kind] or {}) do
        if vim.api.nvim_get_option_value(k, { win = win }) ~= v then
          vim.api.nvim_set_option_value(k, v, { win = win })
        end
      end
    end
  end
end

return FloatingWindow
