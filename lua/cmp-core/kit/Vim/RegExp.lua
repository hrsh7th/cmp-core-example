local RegExp = {}

RegExp.create = setmetatable({
  cache = {}
}, {
  __call = function(self, pattern)
    if not self.cache[pattern] then
      self.cache[pattern] = vim.regex(pattern)
    end
    return self.cache[pattern]
  end
})

function RegExp.match()
end

return RegExp
