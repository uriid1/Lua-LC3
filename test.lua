local vm = require('lc3')

local program = {
0x3000,
0x2202,
0x3202,
0xF025,
0x0005,
0x0000,
}

vm.loadProgram(program, program[1])
vm.run()
