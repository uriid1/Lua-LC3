-- Виртуальная машина LC-3 на Lua
--
--[[
Инструкции
  * Все инструкции по 16 бит

Разбиение полей в инструкции LC-3
--------------------------------------------------
| 15  12 | 11  9 |  8  6  | 5 | 4  3  2 | 1  0   |
| -------+-------+--------+---+----------------- |
| OPCODE |  DR   |  SR1   | M |  OPERAND         |
--------------------------------------------------

Описание инструкций
  * OPCODE - Опкод
  * DR     - Регистр назначения
  * SR1    - Первый источник, Source Register 1
  * M      - Режим: 0 – регистр, 1 – немедленное значение

Битность инструкций
  * OPCODE - Биты 15-12
  * DR     - Биты 11-9
  * SR     - Биты 8-6
  * M      - Бит 5
  * SR2    - Биты 4-0 M == 0
  * imm5   - Биты 4-9 M == 1
--]]

--
local vm = {}

--
-- Отладка
local p = require('pimp')
 :decimalToHexadecimal()

function bitCount(n)
  if n == 0 then return 1 end
  return math.floor(math.log(n, 2)) + 1
end

-- Печать числа как HEX
local function num2hex(number)
  return string.format("%X", number)
end

-- Число в строку бинарного вида
local function num2bin(number, count_bits)
  count_bits = count_bits or bitCount(number)

  -- Преобразуем число в двоичную строку
  local binary = ""
  for i = count_bits, 0, -1 do
    binary = binary .. tostring((number >> i) & 0x1)
  end

  return binary
end

local function addrVal2bits(number)
    -- Преобразуем число в двоичную строку
  local binary = ""
  for i = 15, 0, -1 do
    binary = binary .. tostring((number >> i) & 0x1)
  end

  local data = {
    binary:sub(1, 4),
    binary:sub(5, 8),
    binary:sub(9, 12),
    binary:sub(13, 16),
  }

  return table.concat(data, ' ')
end

-- Число в строку бинарного вида
-- только для инструкций LC3
local function num2bini(number)
  -- Преобразуем число в двоичную строку
  local binary = ""
  for i = 15, 0, -1 do
    binary = binary .. tostring((number >> i) & 0x1)
  end

  local data = {
    opcode = binary:sub(1, 4),
    param1 = binary:sub(5, 8),
    param2 = binary:sub(9, 11),
    m = binary:sub(12, 12),
    param3 = binary:sub(13, 16),
  }

  return data
end

-- Печать числа с учетом флага, если оно отрицательное
local function num2bin_flag(number)
  -- Преобразуем число в двоичную строку
  local binary = ""
  for i = 15, 0, -1 do
    binary = binary .. tostring((number >> i) & 0x1)
  end

  local data = {
    flag = binary:sub(16, 16),
    value = binary:sub(1, 15)
  }

  return data
end
--

-- Константы
local MEMORY_SIZE = 65536 -- 2^16 ячеек памяти

-- Инициализация памяти и регистров
-- Регистры занимают 3 бита (значения от 0 до 7)
--
vm.memory = {}

-- Заполняем память нулями
for i = 0, MEMORY_SIZE - 1 do
  vm.memory[i] = 0
end

-- x0  x1  x2  x3  x4  x5  x6  x7   x8   x9    xA
-- R0, R1, R2, R3, R4, R5, R6, R7, RPC, RCND, RCNT
local OPCODE_PC = 0x8
local OPCOD_COND = 0x9
vm.registers = {
  [0x0] = 0,  -- R0
  [0x1] = 0,  -- R1
  [0x2] = 0,  -- R2
  [0x3] = 0,  -- R3
  [0x4] = 0,  -- R4
  [0x5] = 0,  -- R5
  [0x6] = 0,  -- R6
  [0x7] = 0,  -- R7
  [OPCODE_PC] = 0,    -- PC Счётчик команд
  [OPCOD_COND] = 0,  -- COND Регистр флагов условий
  [0xA] = 0,  -- CNT
}

-- Счётчик команд
vm.opcodes = {
  BR   = 0x0,
  ADD  = 0x1,
  LD   = 0x2,
  ST   = 0x3,
  JST  = 0x4,
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

-- Флаги для обработки условий
vm.flags = {
  FP = 1 << 0,  -- 2
  FZ = 1 << 1,  -- 1
  FN = 1 << 2   -- 4
}

-- Trap Vector
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

-- Обновление регистра флагов
function vm.updateCondFlag(reg)
  if vm.registers[reg] == 0 then
    -- Значение в reg равно нулю
    vm.registers[OPCOD_COND] = vm.flags.FZ
  elseif vm.registers[reg] > 0 then
    -- Значение в reg положительное число
    vm.registers[OPCOD_COND] = vm.flags.FP
  else
    -- Значение в reg отрицательное число
    vm.registers[OPCOD_COND] = vm.flags.FN
  end
end

-- Загрузка значения из памяти
function vm.readMem(addr)
  return vm.memory[addr]
end

-- Запись значения в память по адресу
function vm.writeMem(addr, value)
  vm.memory[addr] = value
end

-- Загрузка программы в память
function vm.loadProgram(program, startAddr)
  program[1] = nil
  startAddr = startAddr and startAddr - 1 or 1
  vm.registers[OPCODE_PC] = startAddr + 1

  print("[Addr]   Value  Binary Addr")
  print("-----------------------------------")
  for i = 2, #program do
    vm.memory[startAddr + (i - 1)] = program[i]

    print(
      string.format("[0x%04X] 0x%04X %s",
        startAddr + (i - 1),
        program[i],
        addrVal2bits(program[i]))
    )
  end
  print("-----------------------------------")
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

-- Преобразование числа с знаковым расширением
local function signedNumber(value)
  -- Проверка на знаковое расширение загруженного значения
  -- 0x8000 = 0b1000000000000000 = 32768
  -- бит 15 (старший бит) в 16-битном числе
  if (value & 0x8000) ~= 0 then
    -- (0xFFFF + 1) = 0x10000 = 0b1_0000000000000000 = 65536
    value = value - (0xFFFF + 1)
  end

  return value
end

-- Инструкция TRAP OUT
local function trap_out()
  local char = vm.registers[0] & 0xFF
  io.write(string.char(char))
  io.flush()
end

--
local function trap_puts()
  local addr = vm.registers[0]
  for i = addr, #vm.memory do
    local char = vm.memory[i]
    if char == 0 then
      break
    end

    io.write(string.char(char))
  end
  io.flush()
end

-- Основной цикл
function vm.run()
  while true do
    -- Текущий указатель на инструкцию в памяти
    local PC = vm.registers[OPCODE_PC]
    -- Инструкция по указателю
    local instruction = vm.memory[PC]
    -- Увеличение указателя на следующую инструкцию
    vm.registers[OPCODE_PC] = vm.registers[OPCODE_PC] + 1

    -- Опкод (первые 4 бита)
    local opcode = instruction >> 12
    io.write(opcode, " ")

    if opcode == vm.opcodes.BR then
      local condFlag = (instruction >> 9) & 0x7
      local pcOffset = getOffset9(instruction)

      -- Если флаг условий совпадает с текущим состоянием флагов, выполняем переход
      if (condFlag & vm.registers[OPCOD_COND]) ~= 0 then
        vm.registers[OPCODE_PC] = vm.registers[OPCODE_PC] + pcOffset
      end

    elseif opcode == vm.opcodes.ADD then
      -- Регистр назначения
      local dr = getDr(instruction)
      -- Первый источник
      local sr1 = getSr1(instruction)
      -- Флаг режима
      local immFlag = getImmFlag(instruction)

      -- Второй источник (SR2) - если флаг равен 0
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
      vm.writeMem(vm.registers[OPCODE_PC] + offset9, value)

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
      vm.memory[address] = vm.registers[sr]

    elseif opcode == vm.opcodes.STI then
      -- Регистр, данные из которого записываются в память
      local sr = getSr(instruction)
      -- Смещение для получения адреса указателя
      local offset9 = getOffset9(instruction)
      -- Адрес указателя
      local addr = vm.registers[OPCODE_PC] + offset9
      -- Указатель (реальный адрес хранения)
      local targetAddr = vm.memory[addr]
      -- Запись данных в конечный адрес
      vm.writeMem(targetAddr, vm.registers[sr])

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

      vm.registers[dr] = vm.registers[dr] ~ vm.registers[sr1]

      vm.updateCondFlag(dr)

    elseif opcode == vm.opcodes.LDI then
      -- Регистр назначения
      local dr = getDr(instruction)
      -- Смещение от PC
      local offset9 = getOffset9(instruction)
      -- Адрес указателя в памяти
      local addr = vm.registers[OPCODE_PC] + offset9
      -- Реальный адрес данных из памяти
      local realAddress = vm.memory[addr]
      -- Загружаем данные по найденному адресу
      vm.registers[dr] = vm.memory[realAddress]

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

      -- Вывод значения из R0
      if trapVector == vm.trapVector.OUT then
        trap_out()
      elseif trapVector == vm.trapVector.PUTS then
        -- Печать символов, пока не встретится 0x0000
        trap_puts()
      elseif trapVector == vm.trapVector.HALT then
        -- Остановка выполнения программы
        break
      end
    end
  end

  p(vm.memory[0x3004])
end

return vm