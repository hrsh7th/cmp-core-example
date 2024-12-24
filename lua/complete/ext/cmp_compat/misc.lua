local misc = {}

---Safe version of vim.str_utfindex
---@param text string
---@param vimindex integer|nil
---@return integer
misc.to_utfindex = function(text, vimindex)
  vimindex = vimindex or #text + 1
  return vim.str_utfindex(text, math.max(0, math.min(vimindex - 1, #text)))
end

return misc
