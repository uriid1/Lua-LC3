.ORIG x3000
  LD R1, N1        ; Загрузить первое число
  LD R2, N2        ; Загрузить второе число

  NOT R2, R2       ; Инвертируем R2
  ADD R2, R2, #1   ; Получаем -R2
  ADD R3, R1, R2   ; Вычисляем R1 - R2

  BRz PRINT_EQUAL  ; Если R3 == 0, числа равны
  BR END_PROGRAM

PRINT_EQUAL
  EQUAL     .STRINGZ "Equal\n"
  LEA R0, EQUAL
  PUTS

END_PROGRAM
  NOT_EQUAL .STRINGZ "Not equal\n"
  LEA R0, NOT_EQUAL
  PUTS
  HALT

N1 .FILL 1
N2 .FILL 2

.END
