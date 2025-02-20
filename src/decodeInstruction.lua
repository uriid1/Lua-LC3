-- Знаковое 11-битное смещение
local function getOffset11(instruction)
  local offset11 = instruction & 0x7FF

  -- Проверка на знак минус
  -- Проверка на знак (если 10-й бит == 1, то число отрицательное)
  if (offset11 >> 10) == 1 then
    offset11 = offset11 - 0x800
  end

  return offset11
end

-- Знаковое 9-битное смещение
local function getOffset9(instruction)
  local offset9 = instruction & 0x1FF

  -- Проверка на знак минус
  -- Если 9-й бит установлен (отрицательное число), вычитаем 512 (0x200)
  if (offset9 >> 8) == 1 then
    offset9 = offset9 - 0x200
  end

  return offset9
end

-- Знаковое 6-битное смещение
local function getOffset6(instruction)
  local offset6 = instruction & 0x3F

  -- Проверка на знак минус
  -- Если 6-й бит установлен (отрицательное число), вычитаем 64 (0x40)
  if (offset6 >> 5) == 1 then
    offset6 = offset6 - 0x40
  end

  return offset6
end

-- Функция получает регистр назначения
local function getDr(instruction)
  return (instruction >> 9) & 0x7
end

-- Получение 5-го бита
-- для определения какую требуется выполнить инструкцию
local function getImmFlag(instruction)
  return (instruction >> 5) & 1
end

-- Источник
-- как правило, для команд ST, STI, STR
local function getSr(instruction)
  return (instruction >> 9) & 0x7
end

-- Первый источник (регистр)
local function getSr1(instruction)
  return (instruction >> 6) & 0x7
end

-- Второй источник (регистр)
local function getSr2(instruction)
  return instruction & 0x7
end

-- Базовый регистр
local function getBaser(instruction)
  return (instruction >> 6) & 0x7
end

local function getCondFlag(instruction)
  return (instruction >> 9) & 0x7
end

-- Получение немедленного значения
local function getImm5(instruction)
  -- Оставляем только 5 младших бит
  -- 31 = 0001 1111
  local imm5 = instruction & 31

  -- Знаковое расширение
  -- если старший 4-бит установлен
  if (imm5 & 16) ~= 0 then
    -- Преобразование в отрицательное число
    imm5 = imm5 - 32
  end

  return imm5
end

local opcodes = {
  BR   = 0x0,
  ADD  = 0x1,
  LD   = 0x2,
  ST   = 0x3,
  JSR  = 0x4,
  AND  = 0x5,
  LDR  = 0x6,
  STR  = 0x7,
  RTI  = 0x8,
  NOT  = 0x9,
  LDI  = 0xA,
  STI  = 0xB,
  JMP  = 0xC,
  RES  = 0xD,
  LEA  = 0xE,
  TRAP = 0xF
}

local function decodeInstruction(instruction)
  local instStr
  local opcode = instruction >> 12

  if opcode == opcodes.BR then
    local cond = getCondFlag(instruction)
    local flags = ''
    if (cond & 0x4) ~= 0 then flags = flags .. 'n' end
    if (cond & 0x2) ~= 0 then flags = flags .. 'z' end
    if (cond & 0x1) ~= 0 then flags = flags .. 'p' end
    instStr = string.format('BR%s #%d', flags, getOffset9(instruction))

  elseif opcode == opcodes.ADD then
    local dr = getDr(instruction)
    local sr1 = getSr1(instruction)
    local immFlag = getImmFlag(instruction)

    if immFlag == 0 then
      local sr2 = getSr2(instruction)
      instStr = string.format('ADD R%d, R%d, R%d', dr, sr1, sr2)
    else
      local imm5 = getImm5(instruction)
      instStr = string.format('ADD R%d, R%d, #%d', dr, sr1, imm5)
    end

  elseif opcode == opcodes.LD then
    instStr = string.format(
      'LD R%d, #%d',
      getDr(instruction),
      getOffset9(instruction)
    )

  elseif opcode == opcodes.ST then
    instStr = string.format(
      'ST R%d, #%d',
      getSr(instruction),
      getOffset9(instruction)
    )

  elseif opcode == opcodes.JSR then
    local jsrMode = (instruction >> 11) & 0x1

    if jsrMode == 1 then
      instStr = string.format('JSR #%d', getOffset11(instruction))
    else
      instStr = string.format('JSRR R%d', getBaser(instruction))
    end

  elseif opcode == opcodes.AND then
    local dr = getDr(instruction)
    local sr1 = getSr1(instruction)
    local immFlag = getImmFlag(instruction)

    if immFlag == 0 then
      local sr2 = getSr2(instruction)
      instStr = string.format('AND R%d, R%d, R%d', dr, sr1, sr2)
    else
      local imm5 = getImm5(instruction)
      instStr = string.format('AND R%d, R%d, #%d', dr, sr1, imm5)
    end

  elseif opcode == opcodes.LDR then
    instStr = string.format(
      'LDR R%d, R%d, #%d',
      getDr(instruction),
      getBaser(instruction),
      getOffset6(instruction)
    )

  elseif opcode == opcodes.STR then
    instStr = string.format(
      'STR R%d, R%d, #%d',
      getSr(instruction),
      getBaser(instruction),
      getOffset6(instruction)
    )

  elseif opcode == opcodes.RTI then
    instStr = 'RTI'

  elseif opcode == opcodes.NOT then
    instStr = string.format(
      'NOT R%d, R%d',
      getDr(instruction),
      getSr1(instruction)
    )

  elseif opcode == opcodes.LDI then
    instStr = string.format(
      'LDI R%d, #%d',
      getDr(instruction),
      getOffset9(instruction)
    )

  elseif opcode == opcodes.STI then
    instStr = string.format(
      'STI R%d, #%d',
      getSr(instruction),
      getOffset9(instruction)
    )

  elseif opcode == opcodes.JMP then
    instStr = string.format(
      'JMP R%d', getBaser(instruction)
    )

  elseif opcode == opcodes.RES then
    instStr = 'RES'

  elseif opcode == opcodes.LEA then
    instStr = string.format(
      'LEA R%d, #%d',
      getDr(instruction),
      getOffset9(instruction)
    )

  elseif opcode == opcodes.TRAP then
    local trapVect = instruction & 0xFF
    local vect

    if trapVect == 0x25 then
      vect = 'HALT'
    elseif trapVect == 0x20 then
      vect = 'GETC'
    elseif trapVect == 0x21 then
      vect = 'OUT'
    elseif trapVect == 0x22 then
      vect = 'PUTS'
    elseif trapVect == 0x23 then
      vect = 'TIN'
    elseif trapVect == 0x24 then
      vect = 'PUTSP'
    elseif trapVect == 0x26 then
      vect = 'INU16'
    elseif trapVect == 0x27 then
      vect = 'OUTU16'
    else
      vect = 'Unknown'
    end

    instStr = string.format(
      'TRAP %s', vect
    )

  else
    instStr = 'Unknown'
  end

  return instStr
end

return decodeInstruction
