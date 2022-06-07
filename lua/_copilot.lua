local copilot = {}

copilot.lsp_start_client = function(cmd, handler_names)
  local handlers = {}
  local id
  for _, name in ipairs(handler_names) do
    handlers[name] = function(err, result)
      if result then
        local retval = vim.call('copilot#agent#LspHandle', id, {method = name, params = result})
        if retval ~= 0 then return retval end
      end
    end
  end
  id = vim.lsp.start_client({
    cmd = cmd,
    name = 'copilot',
    handlers = handlers,
    get_language_id = function(bufnr, filetype)
      return vim.call('copilot#doc#LanguageForFileType', filetype)
    end,
    on_init = function(client, initialize_result)
      vim.call('copilot#agent#LspInit', client.id, initialize_result)
    end,
    on_exit = function(code, signal, client_id)
      vim.call('copilot#agent#LspExit', client_id, code, signal)
    end
  })
  return id
end

copilot.lsp_request = function(client_id, method, params, bufnr)
  bufnr = bufnr or 0
  vim.lsp.buf_attach_client(bufnr, client_id)
  params.uri = vim.uri_from_bufnr(bufnr)
  local _, id
  _, id = vim.lsp.get_client_by_id(client_id).request(method, params, function(err, result)
    vim.call('copilot#agent#LspResponse', client_id, {id = id, error = err, result = result}, bufnr)
  end)
  return id
end

copilot.rpc_request = function(client_id, method, params)
  local _, id
  _, id = vim.lsp.get_client_by_id(client_id).rpc.request(method, params, function(err, result)
    vim.call('copilot#agent#LspResponse', client_id, {id = id, error = err, result = result})
  end)
  return id
end

copilot.rpc_notify = function(client_id, method, params)
  return vim.lsp.get_client_by_id(client_id).rpc.notify(method, params)
end

return copilot
