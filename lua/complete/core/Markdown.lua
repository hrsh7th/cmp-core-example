-- Credits: https://github.com/folke/noice.nvim/blob/main/lua/noice/text/treesitter.lua

local kit = require('complete.kit')

---@alias complete.core.Markdown.Range { [1]: integer, [2]: integer, [3]: integer, [4]: integer }
---@alias complete.core.Markdown.Conceal { row: integer, col: integer, end_row: integer, end_col: integer, conceal: string }

---@class complete.core.Markdown.CodeBlockSection
---@field public type 'code_block'
---@field public language? string
---@field public contents string[]
---@class complete.core.Markdown.MarkdownSection
---@field public type 'markdown'
---@field public contents string[]
---@class complete.core.Markdown.SeparatorSection
---@field public type 'separator'
---@alias complete.core.Markdown.Section complete.core.Markdown.CodeBlockSection|complete.core.Markdown.MarkdownSection|complete.core.Markdown.SeparatorSection

local Markdown = {}

local escaped_characters = { '\\', '`', '*', '_', '{', '}', '[', ']', '<', '>', '(', ')', '#', '+', '-', '.', '!', '|' }

---Trim empty lines.
---@param contents string[]
---@return string[]
local function trim_empty_lines(contents)
  contents = kit.clone(contents)
  for i = 1, #contents do
    if contents[i] == '' then
      table.remove(contents, i)
      i = i - 1
    else
      break
    end
  end
  for i = #contents, 1, -1 do
    if contents[i] == '' then
      table.remove(contents, i)
    else
      break
    end
  end
  return contents
end

---Prepare markdown contents.
---@param raw_contents string[]
---@return string[], table<string, complete.core.Markdown.Range[]>, complete.core.Markdown.Conceal[]
local function prepare_markdown_contents(raw_contents)
  ---@type complete.core.Markdown.Section[]
  local sections = {}

  -- parse sections.
  do
    ---@type complete.core.Markdown.Section
    local current = {
      type = 'markdown',
      contents = {},
    }
    for _, content in ipairs(raw_contents) do
      if content:match('^```') then
        if current.type == 'markdown' then
          table.insert(sections, current)
          local language = content:match('^```(.*)')
          language = language:gsub('^%s*', ''):gsub('%s*$', '')
          language = language ~= '' and language or nil
          current = {
            type = 'code_block',
            language = language,
            contents = {},
          }
        else
          table.insert(sections, current)
          current = {
            type = 'markdown',
            contents = {},
          }
        end
      else
        if current.type == 'markdown' and content:match('^---+$') then
          table.insert(sections, current)
          table.insert(sections, {
            type = 'separator',
          })
          current = {
            type = 'markdown',
            contents = {},
          }
        else
          table.insert(current.contents, content)
        end
      end
    end
    table.insert(sections, current)
  end

  -- prune sections.
  for i = #sections, 1, -1 do
    local section = sections[i]
    if section.type == 'code_block' then
      section.contents = trim_empty_lines(section.contents)
      if #section.contents == 0 then
        table.remove(sections, i)
      end
    elseif section.type == 'markdown' then
      section.contents = trim_empty_lines(section.contents)
      if #section.contents == 0 then
        table.remove(sections, i)
      end

      -- shrink linebreak for markdown rules.
      for j = #section.contents, 1, -1 do
        if section.contents[j - 1] ~= '' and section.contents[j] == '' then
          table.remove(section.contents, j)
        end
      end
    end
  end

  -- parse annotations.
  local contents = {} ---@type string[]
  local languages = {} ---@type table<string, complete.core.Markdown.Range>
  local conceals = {} ---@type complete.core.Markdown.Conceal[]
  for i, section in ipairs(sections) do
    -- insert empty lines between different sections.
    if i > 1 and #sections > 1 and section.type ~= 'separator' and sections[i - 1].type ~= 'separator' then
      table.insert(contents, '')
    end

    if section.type == 'code_block' then
      local s = #contents + 1
      for _, content in ipairs(section.contents) do
        table.insert(contents, content)
      end
      local e = #contents
      if section.language then
        languages[section.language] = languages[section.language] or {}
        table.insert(languages[section.language], { s - 1, 0, e - 1, #contents[#contents] })
      end
    elseif section.type == 'markdown' then
      local s = #contents + 1
      for _, content in ipairs(section.contents) do
        -- check conceals.
        for j = 1, #content do
          local c = content:sub(j, j)
          if c == '\\' then
            -- escape sequence. @see https://github.com/mattcone/markdown-guide/blob/master/_basic-syntax/escaping-characters.md
            local n = content:sub(j + 1, j + 1)
            if vim.tbl_contains(escaped_characters, n) then
              table.insert(conceals, {
                row = #contents,
                col = j - 1,
                end_row = #contents,
                end_col = j,
                conceal = '',
              })
              j = j + 1
            end
          elseif c:match('%d') then
            -- TODO: hack for nvim's treesitter.
            -- emphasised text with %d pattern does not highlighted correctly. e.g.: `__some_text_123__`
            local n1 = content:sub(j + 1, j + 1)
            local n2 = content:sub(j + 2, j + 2)
            if n1 == '_' and n2 == '_' then
              content = ('%s.%s'):format(content:sub(1, j), content:sub(j + 1))
              table.insert(conceals, {
                row = #contents,
                col = j,
                end_row = #contents,
                end_col = j + 1,
                conceal = '',
              })
              j = j + 2
            end
          end
        end
        table.insert(contents, content)
      end
      local e = #contents
      languages['markdown_inline'] = languages['markdown_inline'] or {}
      table.insert(languages['markdown_inline'], { s - 1, 0, e - 1, #contents[#contents] })
    elseif section.type == 'separator' then
      table.insert(contents, ('─'):rep(vim.o.columns))
    end
  end
  return contents, languages, conceals
end

---Set markdown contents to the buffer.
---@param bufnr integer
---@param ns_id integer
---@param raw_contents string[]
function Markdown.set(bufnr, ns_id, raw_contents)
  local contents, languages, conceals = prepare_markdown_contents(raw_contents)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  for maybe_language, ranges in pairs(languages) do
    local language = vim.treesitter.language.get_lang(maybe_language) or maybe_language
    local parser = vim.treesitter.languagetree.new(bufnr, language)
    ---@diagnostic disable-next-line: invisible
    parser:set_included_regions(vim
      .iter(ranges)
      :map(function(range)
        return { range }
      end)
      :totable())
    for _, range in ipairs(ranges) do
      parser:parse(range)
      parser:for_each_tree(function(tree, ltree)
        local highlighter = vim.treesitter.highlighter.new(ltree, {})
        vim.treesitter.stop(bufnr)
        local highlighter_query = highlighter:get_query(language)
        for capture, node, metadata in highlighter_query:query():iter_captures(tree:root(), bufnr) do
          ---@diagnostic disable-next-line: invisible
          local hl_id = highlighter_query:get_hl_from_capture(capture)
          if hl_id then
            local start_row, start_col, end_row, end_col = node:range(false)

            -- TODO: hack for nvim's treesitter.
            -- native treesitter highlights escaped-string and concealed-text but I don't expected it.
            local conceal = metadata.conceal or metadata[capture] and metadata[capture].conceal
            local capture_name = highlighter_query:query().captures[capture]
            if conceal or vim.tbl_contains({ 'string.escape' }, capture_name) then
              hl_id = nil
            end

            vim.api.nvim_buf_set_extmark(bufnr, ns_id, start_row, start_col, {
              end_row = end_row,
              end_col = end_col,
              hl_group = hl_id,
              priority = tonumber(metadata.priority or metadata[capture] and metadata[capture].priority),
              conceal = conceal,
            })
          end
        end
      end)
    end
  end

  for _, conceal in ipairs(conceals) do
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, conceal.row, conceal.col, {
      end_row = conceal.end_row,
      end_col = conceal.end_col,
      conceal = conceal.conceal,
    })
  end
end

return Markdown
