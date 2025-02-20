; Программа печатет "Hello! This is test :)"

.orig x3000
lea r0, str1
puts
lea r0, str2
puts
lea r0, str3
puts
halt

str1 .stringz "Hello! "
str2 .stringz "This is "
str3 .stringz "test :) "
.end
