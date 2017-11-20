SKYNET_PATH = ./skynet

include $(SKYNET_PATH)/platform.mk

CC = cc
CFLAGS = -g -Wall -O2
LUA_PATH = $(SKYNET_PATH)/3rd/lua
SKYNET_SRC_PATH = $(SKYNET_PATH)/skynet-src
CSERVICE_PATH = cservice
CSERVICE = logger package

LUACLIB_PATH = luaclib
LUACLIB = webclient crypt
LUACLIB_3RD = cjson

all : $(foreach v, $(CSERVICE), $(CSERVICE_PATH)/$(v).so) \
		$(foreach v, $(LUACLIB), $(LUACLIB_PATH)/$(v).so) \
		$(foreach v, $(LUACLIB_3RD), $(LUACLIB_PATH)/$(v).so)

.PHONY: all

$(CSERVICE_PATH) :
	mkdir $(CSERVICE_PATH)

$(LUACLIB_PATH) :
	mkdir $(LUACLIB_PATH)

define CSERVICE_TEMP
  $$(CSERVICE_PATH)/$(1).so : src/service/$(1).c | $$(CSERVICE_PATH)
	$$(CC) $$(CFLAGS) $$(SHARED) $$< -o $$@ -I$$(SKYNET_SRC_PATH)
endef

$(foreach v, $(CSERVICE), $(eval $(call CSERVICE_TEMP,$(v))))

define LUACLIB_TEMP
  $$(LUACLIB_PATH)/$(1).so : src/lualib/$(1).c | $$(LUACLIB_PATH)
	$$(CC) $$(CFLAGS) $$(SHARED) $$< -o $$@ -I$$(LUA_PATH) -I$$(SKYNET_SRC_PATH) -lcurl
endef

$(foreach v, $(LUACLIB), $(eval $(call LUACLIB_TEMP,$(v))))

$(LUACLIB_PATH)/cjson.so : | $(LUACLIB_PATH)
	cd src/lualib/cjson && $(MAKE) LUA_INCLUDE_DIR=../../../$(LUA_PATH) CC=$(CC) CJSON_LDFLAGS="$(SHARED)" && cd ../../.. && cp src/lualib//cjson/cjson.so $@

clean :
	rm -f $(CSERVICE_PATH)/*.so
	rm -f $(LUACLIB_PATH)/*.so
