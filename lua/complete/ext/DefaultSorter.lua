---Compare two items.
---@param a complete.core.Match
---@param b complete.core.Match
---@return boolean|nil
local function compare(a, b)
  if a.score ~= b.score then
    return a.score > b.score
  end
  local sort_text_a = a.item:get_sort_text()
  local sort_text_b = b.item:get_sort_text()
  if #sort_text_a ~= #sort_text_b then
    return #sort_text_a < #sort_text_b
  end
  return sort_text_a < sort_text_b
end

local DefaultSorter = {}

---Sort matches.
---@param matches complete.core.Match[]
---@return complete.core.Match[]
function DefaultSorter.sorter(matches)
  table.sort(matches, compare)
  return matches
end

return DefaultSorter
