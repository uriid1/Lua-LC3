-- Компилятор (ассемблер) LC-3 на Lua 5.4
local vm = require('lc3')
local p = require('pimp')
  :decimalToHexadecimal()

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

-- Функция для парсинга числового литерала.
-- Если литерал начинается с '#' — десятичное число,
-- если с 'x' или 'X' — шестнадцатеричное.
local function parseNumber(token)
  token = token:upper()

  if token:sub(1, 1) == "#" then
    return tonumber(token:sub(2), 10)
  elseif token:sub(1, 1) == "X" then
    return tonumber(token:sub(2), 16)
  else
    return tonumber(token)
  end
end

-- Парсинг числового аргументы (смещения) в нужном разряде
local function parseImmediate(token, bitSize)
  local value = parseNumber(token)

  if not value then
    error("Ошибка: Ожидалось числовое значение, получено: " .. tostring(token))
  end

  -- Проверяем допустимые границы значений (знаковое число)
  local minVal = -(2 ^ (bitSize - 1))     -- Например, для 6 бит: -32
  local maxVal = (2 ^ (bitSize - 1)) - 1  -- Например, для 6 бит: 31

  if value < minVal or value > maxVal then
    error(
      string.format(
        "Ошибка: Число %d выходит за пределы [%d, %d] для %d бит.",
        value, minVal, maxVal, bitSize)
      )
  end

  -- Преобразуем в беззнаковый формат LC-3 (для хранения в машинном коде)
  if value < 0 then
    -- Преобразование отрицательных чисел в 2's complement
    value = value + (2 ^ bitSize)
  end

  return value
end

-- Парсинг регистров R0..R7.
local function parseRegister(token)
  token = token:upper()

  if token:sub(1, 1) ~= "R" then
    error("Неверное обозначение регистра: " .. token)
  end

  local num = tonumber(token:sub(2))
  if not num or num < 0 or num > 7 then
    error("Регистровое число вне диапазона (0..7): " .. token)
  end

  return num
end

-- Функция для проверки, является ли токен известной командой (опкодом)
local function isOpcode(token)
  local knownOpcodes = {
    ADD = true,
    AND = true,
    BR = true,
    BRN = true,
    BRZ = true,
    BRP = true,
    BRNZ = true,
    BRNP = true,
    BRZP = true,
    BRNZP = true,
    JMP = true,
    JSR = true,
    JSRR = true,
    LD = true,
    LDI = true,
    LDR = true,
    LEA = true,
    NOT = true,
    RET = true,
    ST = true,
    STI = true,
    STR = true,
    TRAP = true,
    OUT = true,
    IN = true,
    PUTS = true,
    GETC = true,
    HALT = true
  }

  return knownOpcodes[token] or false
end

-- Удаление комментариев и возврат таблицы с очищенными строками
local function rmComments(source)
  local lines = {}

  for line in source:gmatch("[^\r\n]+") do
    local clean = line:gsub(";.*", "")

    clean = trim(clean)

    if clean ~= "" then
      table.insert(lines, clean)
    end
  end

  return lines
end

-- Разбиение строки на токены (слова)
local function tokenize(line)
  local tokens = {}

  for token in line:gmatch("%S+") do
    token = token:gsub(",$", "")  -- удаление завершающей запятой
    table.insert(tokens, token)
  end

  return tokens
end

--
local labels = {}    -- Таблица меток: имя -> адрес
local program = {}   -- Таблица строк программы: { address, tokens, оригинальная строка, tokenIndex }
local orig = nil     -- Начальный адрес из .ORIG
local pc = nil       -- Счётчик адреса

-- Первый проход: разбиение на строки и токены, разрешение меток.
--
local function processTokens(lines)
  for _, line in ipairs(lines) do
    local tokens = tokenize(line)

    if #tokens == 0 then
      goto continue
    end

    local token0 = tokens[1]:upper()

    if token0 == ".ORIG" then
      orig = parseNumber(tokens[2])

      -- Установка счетчика
      pc = orig

      table.insert(program, {
        address = pc,
        tokens = tokens,
        line = line
      })

    elseif token0 == ".END" then
      table.insert(program, {
        address = pc,
        tokens = tokens,
        line = line
      })

      break

    else
      -- Если первый токен не является директивой и не опкодом,
      -- считаем его меткой. В этом случае опкод находится во втором токене.
      local tokenIndex = 1
      local possibleLabel = tokens[1]
      local upperToken = possibleLabel:upper()

      if upperToken:sub(1, 1) ~= "." and not isOpcode(upperToken) then
        if labels[possibleLabel] then
          error("Дублирование метки: " .. possibleLabel)
        end

        labels[possibleLabel] = pc
        tokenIndex = tokenIndex + 1
      end

      -- Если после метки в строке нет токенов, пропускаем строку.
      if tokenIndex > #tokens then
        goto continue
      end

      table.insert(program, {
        address = pc,
        tokens = tokens,
        line = line,
        tokenIndex = tokenIndex
      })

      local op = tokens[tokenIndex]:upper()

      if op == ".STRINGZ" then
        local str = line:match('"(.-)"')

        if not str then
          error("Неверная директива .STRINGZ: " .. line)
        end

        pc = pc + #str
      else
        pc = pc + 1
      end
    end

    ::continue::
  end
end

-- Основная функция компиляции (ассемблирования)
-- На вход подаётся исходная программа LC-3 в виде строки
-- Возвращается таблица с начальным адресом (orig) и массивом машинных слов
local function compile(source)
  -- Очистка комментариев
  local lines = rmComments(source)

  -- Первый проход: разбиение на строки и токены, разрешение меток
  --
  processTokens(lines)

  -- Второй проход: генерация машинного кода
  --
  local machine = {}

  for _, entry in ipairs(program) do
    local tokens = entry.tokens
    local idx = entry.tokenIndex or 1
    local op = tokens[idx] and tokens[idx]:upper()
    local addr = entry.address

    if op == ".ORIG" then
      local operand = tokens[idx + 1]
      local value = parseNumber(operand)

      -- Обработка ошибок
      if value == nil then
        error("Invalid parse .ORIG: " .. tostring(operand))
      end

      table.insert(machine, {
        address = addr,
        word = value
      })

    elseif op == ".END" then
      break

    elseif op == ".FILL" then
      local operand = tokens[idx + 1]
      local value = nil

      if labels[operand] then
        value = labels[operand]
      else
        value = parseNumber(operand)
      end

      table.insert(machine, {
        address = addr,
        word = value & 0xFFFF
      })

    elseif op == ".STRINGZ" then
      local str = entry.line:match('"(.-)"')

      if not str then
        error("Неверная директива .STRINGZ: " .. entry.line)
      end

      local currentAddr = addr
      local i = 1
      while i < #str do
        local ch = str:byte(i)

        -- Обработка "/n"
        -- 92 это "/"
        -- 110 это "n"
        if ch == 92 and str:byte(i + 1) == 110 then
          ch = 10
          -- Пропуск символа, т.е "n"
          i = i + 1
        end

        table.insert(machine, {
          address = currentAddr,
          word = ch
        })

        currentAddr = currentAddr + 1
        i = i + 1
      end

      -- Завершающий ноль
      currentAddr = currentAddr + 1

      table.insert(machine, {
        address = currentAddr,
        word = 0
      })

    else
      -- Обработка инструкций
      if op == "ADD" then
        -- Синтаксис: ADD DR, SR1, SR2  или  ADD DR, SR1, imm5
        local dr = parseRegister(tokens[idx + 1])
        local sr1 = parseRegister(tokens[idx + 2])
        local operand = tokens[idx + 3]
        local word = 0

        word = (vm.opcodes.ADD << 12) | (dr << 9) | (sr1 << 6)

        if operand:upper():sub(1, 1) == "R" then
          local sr2 = parseRegister(operand)
          word = word | sr2

        else
          word = word | (1 << 5)

          local imm = parseNumber(operand)
          if imm < -16 or imm > 15 then
            error("Неверное значение immed в ADD по адресу " .. addr)
          end

          imm = imm & 0x1F
          word = word | imm
        end

        table.insert(machine, {
          address = addr,
          word = word
        })

      elseif op == "LD" then
        -- Синтаксис: LD DR, LABEL
        local dr = parseRegister(tokens[idx + 1])
        local operand = tokens[idx + 2]
        local value = nil

        if labels[operand] then
          value = labels[operand]
        else
          value = parseNumber(operand)
        end

        local offset = value - (addr + 1)
        if offset < -256 or offset > 255 then
          error("PCoffset вне диапазона в LD по адресу " .. addr)
        end

        offset = offset & 0x1FF
        local word = (vm.opcodes.LD << 12) | (dr << 9) | offset

        table.insert(machine, {
          address = addr,
          word = word
        })

      elseif op == "ST" then
        -- Синтаксис: ST SR, LABEL
        local sr = parseRegister(tokens[idx + 1])
        local label = tokens[idx + 2]

        local labelAddress = labels[label]
        local offset = labelAddress - (addr + 1)

        -- Ограничение до 9 бит
        offset = offset & 0x1FF

        local word = (vm.opcodes.ST << 12) | (sr << 9) | offset

        table.insert(machine, {
          address = addr,
          word = word
        })

      elseif op == "STR" then
        -- Синтаксис: STR SR, BaseR, offset6
        local sr = parseRegister(tokens[idx + 1])
        local baser = parseRegister(tokens[idx + 2])
        local offset = parseImmediate(tokens[idx + 3], 6) -- Знаковое 6-битное число

        -- Ограничение до 6 бит
        offset = offset & 0x3F

        local word = (vm.opcodes.STR << 12) | (sr << 9) | (baser << 6) | offset

        table.insert(machine, {
          address = addr,
          word = word
        })

      elseif op == "STI" then
        -- Синтаксис: STI SR, LABEL
        local sr = parseRegister(tokens[idx + 1])
        local label = tokens[idx + 2]

        local labelAddress = labels[label]
        local offset = labelAddress - (addr + 1)

        -- Ограничение до 9 бит
        offset = offset & 0x1FF

        local word = (vm.opcodes.STI << 12) | (sr << 9) | offset

        table.insert(machine, {
          address = addr,
          word = word
        })


      elseif op == "AND" then
        -- Синтаксис: AND DR, SR1, SR2  или  AND DR, SR1, imm5
        local dr = parseRegister(tokens[idx + 1])
        local sr1 = parseRegister(tokens[idx + 2])
        local operand = tokens[idx + 3]
        local word = 0

        word = (vm.opcodes.AND << 12) | (dr << 9) | (sr1 << 6)

        -- & двух регистров и сохранение в регистре назначения
        if operand:upper():sub(1, 1) == "R" then
          local sr2 = parseRegister(operand)
          word = word | sr2

        else
          -- & регистра и числа и сохранение в регистре назначения
          word = word | (1 << 5)

          local imm = parseNumber(operand)
          if imm < -16 or imm > 15 then
            error("Неверное значение immed в ADD по адресу " .. addr)
          end

          imm = imm & 0x1F
          word = word | imm
        end

        table.insert(machine, {
          address = addr,
          word = word
        })

      elseif op == "LEA" then
        -- Синтаксис: LEA LD, LABEL
        local dr = parseRegister(tokens[idx + 1])
        local label = tokens[idx + 2]
        local labelAddress = labels[label]
        local offset = labelAddress - (addr + 1)

        if offset < -256 or offset > 255 then
          error("PCoffset вне диапазона в LEA по адресу " .. addr)
        end

        -- Ограничение до 9 бит
        offset = offset & 0x1FF

        local word = (vm.opcodes.LEA << 12) | (dr << 9) | offset

        table.insert(machine, {
          address = addr,
          word = word
        })

      elseif op == "LDR" then
        -- Синтаксис: LDR DR, BaseR, offset6
        local dr = parseRegister(tokens[idx + 1])
        local base = parseRegister(tokens[idx + 2])
        local offset = parseNumber(tokens[idx + 3])

        if offset < -32 or offset > 31 then
          error("offset6 вне диапазона в LDR по адресу " .. addr)
        end

        -- Ограничение до 6 бит
        offset = offset & 0x3F

        local word = (vm.opcodes.LDR << 12) | (dr << 9) | (base << 6) | offset

        table.insert(machine, {
          address = addr,
          word = word
        })

      elseif op == "LDI" then
        -- Синтаксис: LDI DR, LABEL
        local dr = parseRegister(tokens[idx + 1])
        local label = tokens[idx + 2]


      elseif op == "NOT" then
        -- Синтаксис: NOT DR, SR1
        local dr = parseRegister(tokens[idx + 1])
        local sr1 = parseRegister(tokens[idx + 2])

        local word = (vm.opcodes.NOT << 12) | (dr << 9) | (sr1 << 6)

        table.insert(machine, {
          address = addr,
          word = word
        })

      elseif op:sub(1, 2) == "BR" then
        -- Синтаксис: BR*, например, BRz, BR, BRnp и.т.д
        local cond = 0
        local suffix = op:sub(3) -- может быть пустым

        if suffix == "" then
          cond = 7 -- если без суффикса, то BRnzp
        else
          if suffix:find("N") or suffix:find("n") then
            cond = cond | 4
          end
          if suffix:find("Z") or suffix:find("z") then
            cond = cond | 2
          end
          if suffix:find("P") or suffix:find("p") then
            cond = cond | 1
          end
        end

        local operand = tokens[idx + 1]
        local value = nil

        if labels[operand] then
          value = labels[operand]
        else
          value = parseNumber(operand)
        end

        local offset = value - (addr + 1)
        if offset < -256 or offset > 255 then
          error("PCoffset вне диапазона в BR по адресу " .. addr)
        end

        -- Ограничение до 9 бит
        offset = offset & 0x1FF

        local word = (cond << 9) | offset

        table.insert(machine, {
          address = addr,
          word = word
        })

      elseif op == "OUT" then
        -- OUT реализуется как TRAP x21
        table.insert(machine, {
          address = addr,
          word = 0xF021
        })

      elseif op == "PUTS" then
        -- HALT реализуется как TRAP x22
        table.insert(machine, {
          address = addr,
          word = 0xF022
        })

      elseif op == "HALT" then
        -- HALT реализуется как TRAP x25
        table.insert(machine, {
          address = addr,
          word = 0xF025
        })

      else
        error("Неизвестный опкод '" .. op .. "' в строке: " .. entry.line)
      end
    end
  end

  return {
    orig = orig,
    machine = machine
  }
end

local function toHex(word)
  return string.format("%04X", word & 0xFFFF)
end

local source = [[
.ORIG x3000          ; Начало программы по адресу x3000

        ; Инициализация данных
        LD R0, DATA1         ; Загрузить значение из DATA1 в R0
        LD R1, DATA2         ; Загрузить значение из DATA2 в R1
        LD R2, POINTER       ; Загрузить адрес из POINTER в R2

        ; Использование LDR для загрузки данных по адресу в R2
        LDR R3, R2, #0       ; Загрузить значение из адреса, указанного в R2, в R3

        ; Использование LDI для косвенной загрузки данных
        LDI R4, INDIRECT     ; Загрузить значение из адреса, указанного в INDIRECT, в R4

        ; Арифметическая операция (сложение)
        ADD R5, R0, R1       ; R5 = R0 + R1

        ; Использование ST для сохранения результата
        ST R5, RESULT        ; Сохранить значение из R5 в RESULT

        ; Использование STR для сохранения данных по адресу в R2
        STR R5, R2, #0       ; Сохранить значение из R5 по адресу, указанному в R2

        ; Использование STI для косвенного сохранения данных
        STI R5, INDIRECT     ; Сохранить значение из R5 по адресу, указанному в INDIRECT

        HALT                ; Остановка программы

         ; Данные
DATA1    .FILL x0005         ; Значение 5
DATA2    .FILL x0003         ; Значение 3
POINTER  .FILL x4000         ; Указатель на адрес x4000
INDIRECT .FILL x4001         ; Косвенный адрес x4001
RESULT   .BLKW 1             ; Резервирование места для результата
.END                 ; Конец программы
]]

local result = compile(source)

print("Начальный адрес: " .. string.format("x%04X", result.orig))
for _, entry in ipairs(result.machine) do
  -- print(string.format("x%X: %s", entry.address, toHex(entry.word)))
  print(string.format("0x%s,", toHex(entry.word)))
end
