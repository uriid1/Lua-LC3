; Программа печатает слово repeat и число от 10 до 9 

.ORIG x3000

LOOP
  LEA R0, text         ; Загрузка адреса строки в R0
  PUTS                 ; Вывод строки

  LD  R1, count        ; Загрузка count в R1
  ADD R1, R1, #-1      ; R1 = R1 - 1
  ST  R1, count        ; count = R1

  BRz END_PROGRAM      ; if R1 == 0 then goto END_PROGRAM

  LD  R2, ASCII_OFFSET ; Загрузка 48 (код '0') в R2
  ADD R0, R1, R2       ; Число в ASCII
  OUT                  ; Печать числа

  LD R0, newline       ; Печать новой строки
  OUT

  LEA R1, LOOP         ; Загрузка адреса LOOP в R1
  JMP R1               ; Переход обратно к LOOP

END_PROGRAM
  HALT

ASCII_OFFSET  .FILL     #48
count         .FILL     #10

text          .STRINGZ  "repeat "
newline       .FILL     xA

.END
