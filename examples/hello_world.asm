.ORIG x3000
    LD R0, NUM_0
    OUT
    LD R0, NUM_1
    OUT
    LD R0, NUM_2
    OUT
    LD R0, NUM_3
    OUT
    LD R0, NUM_4
    OUT
    LD R0, NUM_5
    OUT
    LD R0, NUM_6
    OUT
    LD R0, NUM_7
    OUT
    LD R0, NUM_8
    OUT
    LD R0, NUM_9
    OUT
    LD R0, NUM_10
    OUT
    LD R0, NUM_11
    OUT
    LD R0, NUM_12
    OUT
    HALT

NUM_0 .FILL x0048  ;     'H'
NUM_1 .FILL x0065  ;     'e'
NUM_2 .FILL x006c  ;     'l'
NUM_3 .FILL x006c  ;     'l'
NUM_4 .FILL x006f  ;     'o'
NUM_5 .FILL x0020  ;     ' '
NUM_6 .FILL x0057  ;     'W'
NUM_7 .FILL x006f  ;     'o'
NUM_8 .FILL x0072  ;     'r'
NUM_9 .FILL x006c  ;     'l'
NUM_10 .FILL x0064 ;     'd'
NUM_11 .FILL x0021 ;     '!'
NUM_12 .FILL x000a ;     '\n'
.END
