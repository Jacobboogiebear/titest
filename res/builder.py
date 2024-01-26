import subprocess, os, re

includes = ["#include <ti/screen.h>"]

funcs = ["os_ClrHome", "os_SetCursorPos", "os_PutStrFull"]
fc = ""
with open("./main.c", "r") as c:
	c = c.read()
	for i in funcs:
		e = 'void {}.*\n'.format(i)
		c = re.sub(e, '', c)
	c = re.sub(r'#ifndef __cplusplus\n.*\n#endif\n', '', c)
	# c = "#include \"includer.h\"\n" + c
	for include in includes:
		c = include + "\n" + c
	fc = c
os.remove("./main.c")
with open("./main.c", "w") as f:
	f.write(fc)