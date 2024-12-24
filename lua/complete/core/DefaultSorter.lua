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
  if sort_text_a and not sort_text_b then
    return true
  end
  if not sort_text_a and sort_text_b then
    return false
  end
  if sort_text_a and sort_text_b then
    if sort_text_a ~= sort_text_b then
      return sort_text_a < sort_text_b
    end
  end

  local label_text_a = a.item:get_label_text()
  local label_text_b = b.item:get_label_text()
  if #label_text_a ~= #label_text_b then
    return label_text_a < label_text_b
  end
  if #label_text_a ~= #label_text_b then
    return #label_text_a < #label_text_b
  end
  return a.index < b.index
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
