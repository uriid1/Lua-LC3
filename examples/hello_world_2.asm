.ORIG x3000
  LD R1, PTR        ; Загружаем адрес строки в R1

PRINT_LOOP
  LDR R0, R1, #0    ; Загружаем символ (R1 указывает на текущий символ)
  BRz END_PROGRAM   ; Если символ = 0 (конец строки), выходим
  OUT               ; Выводим символ
  ADD R1, R1, #1    ; Переход к следующему символу
  BR PRINT_LOOP     ; Повторяем цикл

END_PROGRAM
  HALT              ; Завершение

PTR    .FILL    STRING            ; Указатель на строку
STRING .STRINGZ "Hello World!\n"  ; Строка (автоматически добавляет нулевой терминатор)

.END
