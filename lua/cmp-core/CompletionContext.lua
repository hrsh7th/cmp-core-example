---The CompletionContext.
---@class cmp-core.CompletionContext
---@field public row number
---@field public col number
---@field public text string
local CompletionContext = {}
CompletionContext.__index = CompletionContext

---Create new CompletionContext.
---@param row integer
---@param col integer
---@param text string
---@return cmp-core.CompletionContext
function CompletionContext.new(row, col, text)
  local self = setmetatable({}, CompletionContext)
  self.row = row
  self.col = col
  self.text = text
  return self
end

return CompletionContext

