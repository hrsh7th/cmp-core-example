local Buffer = {}

function Buffer.is_filetype(bufnr)
  return vim.api.nvim_buf_get_option(bufnr, 'filetype') == filetype
end

return Buffer
