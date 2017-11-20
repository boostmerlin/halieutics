#include "skynet.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>

struct logger {
	FILE * handle;
	char * filename;
	int close;
};

struct logger *
logger_create(void) {
	struct logger * inst = skynet_malloc(sizeof(*inst));
	inst->handle = NULL;
	inst->close = 0;
	inst->filename = NULL;
	return inst;
}

void
logger_release(struct logger * inst) {
	if (inst->close) {
		fclose(inst->handle);
	}
	skynet_free(inst->filename);
	skynet_free(inst);
}

static int
logger_cb(struct skynet_context * ctx, void * ud, int type, int session, uint32_t source, const void * msg, size_t sz) {
	int off;
	struct timeval tv;
	char buf[64];
	struct logger * inst = ud;
	switch (type) {
	case PTYPE_SYSTEM:
		if (inst->filename) {
			inst->handle = freopen(inst->filename, "a", inst->handle);
		}
		break;
	case PTYPE_TEXT:
		gettimeofday(&tv, NULL);
		off = strftime(buf, sizeof(buf), "%d %b %H:%M:%S.", localtime(&tv.tv_sec));
		off += snprintf(buf+off, sizeof(buf)-off, "%03d [:%08x] ", (int)tv.tv_usec/1000, source);
		fwrite(buf, off, 1, inst->handle);
        if (*((char *)msg) != '<') {
            fwrite("<sys> ", 6, 1, inst->handle);
        }
		fwrite(msg, sz, 1, inst->handle);
		fprintf(inst->handle, "\n");
		fflush(inst->handle);
		break;
	}

	return 0;
}

int
logger_init(struct logger * inst, struct skynet_context * ctx, const char * param) {
	if (param) {
		inst->handle = fopen(param, "w");
		if (inst->handle == NULL) {
			return 1;
		}
		inst->filename = skynet_malloc(strlen(param)+1);
		strcpy(inst->filename, param);
		inst->close = 1;
	} else {
		inst->handle = stdout;
	}
	if (inst->handle) {
		skynet_callback(ctx, inst, logger_cb);
		skynet_command(ctx, "REG", ".logger");
		return 0;
	}
	return 1;
}

