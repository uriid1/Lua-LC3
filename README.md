[Спецификация](spec.md)</br>

## Запуск примеров
```lua
lua5.4 vm examples/2048.obj
```
[Пример игры 2048 взят тут](https://github.com/rpendleton/lc3-2048)

# Компиляция
Написание компилятора на lua ещё не реализовано, поэтому лучше использовать lc3tools.

### Установка lc3as
1. Скачать: [LC-3 Unix Simulator](https://highered.mheducation.com/sites/0072467509/student_view0/lc-3_simulator_lab_manual.html)
 и распаковать
2. cd lc3tools
4. ./configure --installdir $PWD
5. make

`lc3as` - Компилятор ассемблера в объектный файл для виртуальной машины.
