-------------------------------
-- Little Computer 3         --
-- uriid1 2025               --
-------------------------------
local vm = {}

-- Константы
--
local MEMORY_SIZE = 65536 -- 2^16
-- Опкод: регистр флагов условий
local OPCODE_PC = 0x8
-- Опкод: регистр условий
local OPCODE_COND = 0x9
-- Зарезервированные адреса
local OS_KBSR = 0xFE00
local OS_KBDR = 0xFE02

-- Инициализация памяти
--
vm.memory = {}

for i = 0, MEMORY_SIZE - 1 do
  vm.memory[i] = 0
end

-- Регистры
--
vm.registers = {
  [0x0] = 0,  -- R0
  [0x1] = 0,  -- R1
  [0x2] = 0,  -- R2
  [0x3] = 0,  -- R3
  [0x4] = 0,  -- R4
  [0x5] = 0,  -- R5
  [0x6] = 0,  -- R6
  [0x7] = 0,  -- R7
  [OPCODE_PC]   = 0,
  [OPCODE_COND] = 0,
  [0xA] = 0,  -- CNT
}

-- Опкоды инструкций
--
vm.opcodes = {
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

-- Флаги обработки условий
--
vm.flags = {
  FP = 1 << 0,  -- 2
  FZ = 1 << 1,  -- 1
  FN = 1 << 2   -- 4
}

-- Вектор доп.инструкций для TRAP
vm.trapVector = {
  GETC = 0x20,
  OUT = 0x21,
  PUTS = 0x22,
  TIN = 0x23,
  PUTSP = 0x24,
  HALT = 0x25,
  INU16 = 0x26,
  OUTU16 = 0x27,
}

-- Инициализация буфера клавиатуры
--
vm.keyboardBuffer = nil

function vm.checkKB(addr)
  -- Cтатус клавиатуры
  if addr == OS_KBSR then
    if not vm.keyboardBuffer then
      -- Если буфер пуст, блокирующее чтение одного символа
      local input = io.read(1)
      if input and input ~= "" then
        vm.keyboardBuffer = input
      end
    end

    -- Если символ получен
    -- то возвращается значение с установленным старшим битом (отрицательное число)
    if vm.keyboardBuffer then
      return 0x8000
    end

    return 0

  -- Данные клавиатуры
  elseif addr == OS_KBDR then
    if vm.keyboardBuffer then
      local c = string.byte(vm.keyboardBuffer) & 0xFF
      vm.keyboardBuffer = nil
      return c
    end

    return 0
  end
end

--- Чтение значения из памяти по адресу
-- @param addr [integer]
-- @return [integer]
function vm.readMem(addr)
  local kb = vm.checkKB(addr)
  if kb then
    return kb
  end

  return vm.memory[addr]
end

--- Запись значения в память по адресу
-- @param addr [integer]
-- @param value [integer]
-- @return [nil]
function vm.writeMem(addr, value)
  vm.memory[addr] = value & 0xFFFF
end

--- Обработка числа со знаком
-- @param value [integer]
-- @return [nil]
local function signedNumber(value)
  -- бит 15 (старший бит) в 16-битном числе
  -- 0x8000 = 0b1000000000000000 = 32768
  if (value & 0x8000) ~= 0 then
    -- (0xFFFF + 1) = 0x10000 = 0b10000000000000000 = 65536
    value = value - (0xFFFF + 1)
  end

  return value
end

--- Обновление регистра флагов
-- @param reg [integer]
-- @return [nil]
function vm.updateCondFlag(reg)
  local value = signedNumber(vm.registers[reg])

  if value == 0 then
    vm.registers[OPCODE_COND] = vm.flags.FZ
  elseif value > 0 then
    vm.registers[OPCODE_COND] = vm.flags.FP
  else
    vm.registers[OPCODE_COND] = vm.flags.FN
  end
end

--- Знаковое 11-битное смещение
-- @param instruction [integer]
-- @return [integer] offset11
local function getOffset11(instruction)
  local offset11 = instruction & 0x7FF

  -- Проверка на знак минус
  -- Проверка на знак (если 10-й бит == 1, то число отрицательное)
  if (offset11 >> 10) == 1 then
    offset11 = offset11 - 0x800
  end

  return offset11
end

--- Знаковое 9-битное смещение
-- @param instruction [integer]
-- @return [integer] offset9
local function getOffset9(instruction)
  local offset9 = instruction & 0x1FF

  -- Проверка на знак минус
  -- Если 9-й бит установлен (отрицательное число), вычитаем 512 (0x200)
  if (offset9 >> 8) == 1 then
    offset9 = offset9 - 0x200
  end

  return offset9
end

--- Знаковое 6-битное смещение
-- @param instruction [integer]
-- @return [integer] offset6
local function getOffset6(instruction)
  local offset6 = instruction & 0x3F

  -- Проверка на знак минус
  -- Если 6-й бит установлен (отрицательное число), вычитаем 64 (0x40)
  if (offset6 >> 5) == 1 then
    offset6 = offset6 - 0x40
  end

  return offset6
end

--- Функция получает регистр назначения
-- @param instruction [integer]
-- @return [integer] dr
local function getDr(instruction)
  return (instruction >> 9) & 0x7
end

--- Получение 5-го бита
--- для определения какую требуется выполнить инструкцию
-- @param instruction [integer]
-- @return [integer] immFlag
local function getImmFlag(instruction)
  return (instruction >> 5) & 1
end

--- Источник
--- как правило, для команд ST, STI, STR
-- @param instruction [integer]
-- @return [integer] sr
local function getSr(instruction)
  return (instruction >> 9) & 0x7
end

--- Первый источник (регистр)
-- @param instruction [integer]
-- @return [integer] sr1
local function getSr1(instruction)
  return (instruction >> 6) & 0x7
end

--- Второй источник (регистр)
-- @param instruction [integer]
-- @return [integer] sr2
local function getSr2(instruction)
  return instruction & 0x7
end

--- Базовый регистр
-- @param instruction [integer]
-- @return [integer] baser
local function getBaser(instruction)
  return (instruction >> 6) & 0x7
end

--- Флаг условий
-- @param instruction [integer]
-- @return [integer] dr
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

-- Вывод значения из R0
local function trap_out()
  local char = vm.registers[0] & 0xFF
  io.write(string.char(char))
  io.flush()
end

-- Печать символов, пока не встретится 0x0000
local function trap_puts()
  local addr = vm.registers[0]

  for i = addr, MEMORY_SIZE - 1 do
    local char = vm.memory[i]
    io.write(string.char(char))

    if char == 0 then
      break
    end
  end
  io.flush()
end

-- Чтение символа с клавиатуры и сохранение его ASCII-кода в R0
local function trap_getc()
  local input = io.read(1)

  -- print(input)
  if input then
    local ascii_value = string.byte(input)
    vm.registers[0] = ascii_value
  else
    vm.registers[0] = 0
  end
end

local function addrVal2bits(number)
  local binary = ""
  for i = 15, 0, -1 do
    binary = binary .. tostring((number >> i) & 0x1)
  end

  return table.concat({
    binary:sub(1, 4),  binary:sub(5, 8),
    binary:sub(9, 12), binary:sub(13, 16),
  }, ' ')
end

--- Загрузка программы в память
-- @param program [table]
-- @param startAddr [integer]
-- @return [nil]
function vm.loadProgram(program, startAddr, opts)
  opts = opts or {}

  program[1] = nil
  startAddr = startAddr and startAddr - 1 or 1
  vm.registers[OPCODE_PC] = startAddr + 1

  if opts.debug then
    print("[Addr]   Value  Binary Addr")
    print("+----------------------------------+")
  end

  for i = 2, #program do
    local addr = startAddr + (i - 1)
    local instruction = program[i]

    vm.memory[addr] = instruction

    if opts.debug then
      print(
        string.format("[0x%04X] 0x%04X %s",
        addr,
        instruction,
        addrVal2bits(instruction)
      ))
    end
  end

  if opts.debug then
    print("+----------------------------------+")
  end
end

-- Основной цикл
function vm.run()
  while true do
    -- Указатель на инструкцию в памяти
    local PC = vm.registers[OPCODE_PC]
    -- Инструкция по указателю
    local instruction = vm.memory[PC]
    -- Увеличение указателя на следующую инструкцию
    vm.registers[OPCODE_PC] = vm.registers[OPCODE_PC] + 1

    -- Опкод (первые 4 бита)
    local opcode = instruction >> 12

    if opcode == vm.opcodes.BR then
      local condFlag = getCondFlag(instruction)
      local offset9 = getOffset9(instruction)

      -- Если флаг условий совпадает с текущим состоянием флагов, выполняем переход
      if (condFlag & vm.registers[OPCODE_COND]) ~= 0 then
        vm.registers[OPCODE_PC] = vm.registers[OPCODE_PC] + offset9
      end

    elseif opcode == vm.opcodes.ADD then
      -- Регистр назначения
      local dr = getDr(instruction)
      -- Первый источник
      local sr1 = getSr1(instruction)
      -- Флаг режима
      local immFlag = getImmFlag(instruction)

      -- Второй источник (SR2)
      if immFlag == 0 then
        local sr2 = getSr2(instruction)
        vm.registers[dr] = vm.registers[sr1] + vm.registers[sr2]

      elseif immFlag == 1 then
        vm.registers[dr] = vm.registers[sr1] + getImm5(instruction)
      end

      vm.updateCondFlag(dr)

    elseif opcode == vm.opcodes.LD then
      -- Регистр назначения
      local dr = getDr(instruction)
      local offset9 = getOffset9(instruction)

      -- Вычисление адреса в памяти (относительно pc)
      local addr = vm.registers[OPCODE_PC] + offset9
      -- Чтение значения из памяти
      local value = vm.readMem(addr)

      -- Загрузка значения из памяти в регистр
      vm.registers[dr] = signedNumber(value)

      -- Обновление флагов
      vm.updateCondFlag(dr)

    elseif opcode == vm.opcodes.ST then
      -- Регистр с какого берем значение
      local sr = getSr(instruction)
      -- Оффсет куда будет сохранено значение
      local offset9 = getOffset9(instruction)

      local value = vm.registers[sr]
      local addr = vm.registers[OPCODE_PC] + offset9
      vm.writeMem(addr, value)

    elseif opcode == vm.opcodes.JSR then
      -- Флаг JSR или JSRR
      -- Проверка 11 бита, 1 или 0
      local jsrMode = (instruction >> 11) & 0x1

      vm.registers[0x7] = vm.registers[OPCODE_PC]

      -- JSRR
      if jsrMode == 0 then
        local baser = getBaser(instruction)
        vm.registers[OPCODE_PC] = vm.registers[baser]

      -- JSR
      elseif jsrMode == 1 then
        local offset11 = getOffset11(instruction)
        vm.registers[OPCODE_PC] = vm.registers[OPCODE_PC] + offset11
      end

    elseif opcode == vm.opcodes.STR then
      -- Регистр, данные из которого записываются в память
      local sr = getSr(instruction)
      -- Регистр, содержащий базовый адрес
      local baser = getBaser(instruction)
      -- Знаковое 6-битное смещение
      local offset6 = getOffset6(instruction)
      -- Вычисление конечного адреса
      local address = vm.registers[baser] + offset6
      -- Запись данных в память
      vm.writeMem(address, vm.registers[sr])

    elseif opcode == vm.opcodes.STI then
      -- Регистр, данные из которого записываются в память
      local sr = getSr(instruction)
      -- Смещение для получения адреса указателя
      local offset9 = getOffset9(instruction)
      -- Адрес указателя
      local addr = vm.registers[OPCODE_PC] + offset9
      -- Указатель (реальный адрес хранения)
      local targetAddr = vm.readMem(addr)
      -- Запись данных в конечный адрес
      vm.writeMem(targetAddr, vm.registers[sr])

    elseif opcode == vm.opcodes.JMP then
      -- Регистр, в котором адрес для перехода
      local baser = getBaser(instruction)
      local addr = vm.registers[baser]

      vm.registers[OPCODE_PC] = addr

    elseif opcode == vm.opcodes.AND then
      -- Регистр назначения
      local dr = getDr(instruction)
      -- Первый источник
      local sr1 = getSr1(instruction)
      -- Флаг режима
      local immFlag = getImmFlag(instruction)

      -- Второй источник (SR2) - если флаг равен 0
      if immFlag == 0 then
        local sr2 = getSr2(instruction)
        vm.registers[dr] = vm.registers[sr1] & vm.registers[sr2]

      elseif immFlag == 1 then
        vm.registers[dr] = vm.registers[sr1] & getImm5(instruction)
      end

      vm.updateCondFlag(dr)

    elseif opcode == vm.opcodes.NOT then
      -- Регистр назначения
      local dr = getDr(instruction)
      -- Первый источник
      local sr1 = getSr1(instruction)

      vm.registers[dr] = ~vm.registers[sr1]
      vm.updateCondFlag(dr)

    elseif opcode == vm.opcodes.LDI then
      -- Регистр назначения
      local dr = getDr(instruction)
      -- Смещение от PC
      local offset9 = getOffset9(instruction)
      -- Адрес указателя в памяти
      local addr = vm.registers[OPCODE_PC] + offset9
      -- Реальный адрес данных из памяти
      local realAddress = vm.readMem(addr)
      -- Загружаем данные по найденному адресу
      vm.registers[dr] = vm.readMem(realAddress)
      -- Обновление флагов
      vm.updateCondFlag(dr)

    elseif opcode == vm.opcodes.LDR then
      -- Регистр назначения
      local dr = getDr(instruction)
      -- Базовый регистр
      local baser = getBaser(instruction)
      -- Смещение OFFSET6 (знаковое расширение)
      local offset6 = getOffset6(instruction)

      -- Читаем из памяти по адресу (значение BASER + OFFSET6)
      local addr = vm.registers[baser] + offset6

      vm.registers[dr] = vm.readMem(addr)
      -- Обновление флагов
      vm.updateCondFlag(dr)

    elseif opcode == vm.opcodes.LEA then
      local dr = getDr(instruction)
      local offset = getOffset9(instruction)

      -- Адрес по офсету
      local addr = vm.registers[OPCODE_PC] + offset
      -- Установка адреса в регистр назначения
      vm.registers[dr] = addr

    elseif opcode == vm.opcodes.TRAP then
      local trapVector = instruction & 0xFF

      if trapVector == vm.trapVector.GETC then
        trap_getc()
      elseif trapVector == vm.trapVector.OUT then
        trap_out()
      elseif trapVector == vm.trapVector.PUTS then
        trap_puts()
      elseif trapVector == vm.trapVector.HALT then
        -- Остановка выполнения программы
        break
      end
    end
  end
end

return vm
