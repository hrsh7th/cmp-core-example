local DefaultSorter = {}

---Sort matches.
---@param matches complete.core.Match[]
---@return complete.core.Match[]
function DefaultSorter.sorter(matches)
  table.sort(matches, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    local sort_text_a = a.item:get_sort_text()
    local sort_text_b = b.item:get_sort_text()
    if sort_text_a ~= sort_text_b then
      return vim.stricmp(sort_text_a, sort_text_b) < 0
    end
    return false
  end)
  return matches
end

return DefaultSorter
