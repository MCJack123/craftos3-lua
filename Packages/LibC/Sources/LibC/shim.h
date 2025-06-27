#include <math.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <ctype.h>
static int errno_() {return errno;}
static FILE* stdin_() {return stdin;}
static FILE* stdout_() {return stdout;}
static FILE* stderr_() {return stderr;}
static FILE* popen_(const char * path, const char * mode) {return popen(path, mode);}