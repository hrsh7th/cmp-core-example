local kit = require('cmp-core.kit')
local Async = require('cmp-core.kit.Async')

local Keymap = {}

Keymap._callbacks = {}

---Replace termcodes.
---@param keys string
---@return string
function Keymap.termcodes(keys)
  return vim.api.nvim_replace_termcodes(keys, true, true, true)
end

---Set callback for consuming next typeahead.
---@param callback fun()
---@return cmp-core.kit.Async.AsyncTask
function Keymap.next(callback)
  return Keymap.send('', 'in'):next(callback)
end

---Send keys.
---@param keys string
---@param mode string
---@return cmp-core.kit.Async.AsyncTask
function Keymap.send(keys, mode)
  if mode:find('t', 1, true) ~= nil then
    error('Keymap.send: mode must not contain "t"')
  end

  local unique_id = kit.unique_id()
  return Async.new(function(resolve)
    Keymap._callbacks[unique_id] = resolve

    local callback = Keymap.termcodes(('<Cmd>lua require("cmp-core.kit.Vim.Keymap")._resolve(%s)<CR>'):format(unique_id))
    if string.match(mode, 'i') then
      vim.api.nvim_feedkeys(callback, 'in', true)
      vim.api.nvim_feedkeys(keys, mode, true)
    else
      vim.api.nvim_feedkeys(keys, mode, true)
      vim.api.nvim_feedkeys(callback, 'n', true)
    end
  end):catch(function()
    Keymap._callbacks[unique_id] = nil
  end)
end

---Test spec helper.
---@param spec fun(): any
function Keymap.spec(spec)
  local task = Async.resolve():next(Async.async(spec))
  vim.api.nvim_feedkeys('', 'x', true)
  task:sync()
  collectgarbage('collect')
  vim.wait(200, function()
    return true
  end)
end

---Resolve running keys.
---@param unique_id integer
function Keymap._resolve(unique_id)
  Keymap._callbacks[unique_id]()
  Keymap._callbacks[unique_id] = nil
end

return Keymap
