local DocumentSelector = {}

---Check buffer matches the selector.
---@see https://github.com/microsoft/vscode/blob/7241eea61021db926c052b657d577ef0d98f7dc7/src/vs/editor/common/languageSelector.ts#L29
---@param document_selector complete.kit.LSP.DocumentSelector
---@param bufnr string
function DocumentSelector.score(document_selector, bufnr)
  for _, filter in ipairs(document_selector) do
    if filter.notebook then
      -- TODO: Implement notebook filter
    else
      -- @see 
    end
  end
end

return DocumentSelector
