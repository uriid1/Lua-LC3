local function readObj(filepath)
  local program = {}

  local fd = io.open(filepath, 'rb')
  if not fd then
    error('Error io.open: ' .. filepath)
  end

  local addrBytes = fd:read(2)
  if not addrBytes or #addrBytes < 2 then
    error('Error read first bytes')
  end

  -- Bytes to BE
  table.insert(program,
    string.byte(addrBytes, 1) * 256 + string.byte(addrBytes, 2)
  )

  while true do
    local word_bytes = fd:read(2)
    if not word_bytes or #word_bytes < 2 then
      break
    end

    -- Bytes to BE
    table.insert(program,
      string.byte(word_bytes, 1) * 256 + string.byte(word_bytes, 2)
    )
  end

  fd:close()

  return program
end

return readObj
