#include <stdlib.h>
#include "lua.h"
#include "lauxlib.h"

static int 
lbase36enc(lua_State * L) {
    unsigned long n = luaL_checknumber(L, 1);
    char base36[36] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    /* log(2**64) / log(36) = 12.38 => max 13 char + '\0' */
    char buffer[14];
    unsigned int offset = sizeof(buffer);

    buffer[--offset] = '\0';
    do {
        buffer[--offset] = base36[n % 36];
    } while (n /= 36);

    lua_pushstring(L, &buffer[offset]);
    return 1;
}

static int 
lbase36dec(lua_State * L) {
	size_t len;
	const char * s = luaL_checklstring(L, 1, &len);
    if (0 == len) {
		return luaL_error(L, "Can't base36 decode empty string");
    }
    unsigned long n = strtoul(s, NULL, 36);
    lua_pushinteger(L, n);
    return 1;

}


extern int
luaopen_crypt(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{"base36encode", lbase36enc},
		{"base36decode", lbase36dec},
		{NULL, NULL},
	};
	luaL_newlib(L, l);
	return 1;
}

