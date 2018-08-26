MBEDTLS_INC_DIR ?= /usr/include/mbedtls
MBEDTLS_LIB_DIR ?= /usr/lib
MBEDTLS_PROG_DIR ?= /usr/bin
LIBEV_INC_DIR ?= /usr/include
LIBEV_LIB_DIR ?= /usr/lib

CFLAGS := $(CFLAGS) -g -fno-strict-aliasing
WARNING_CFLAGS ?= -Wall -W -Wdeclaration-after-statement
LDFLAGS ?=

LOCAL_CFLAGS = $(WARNING_CFLAGS) -I$(MBEDTLS_INC_DIR) -I$(LIBEV_INC_DIR) -D_FILE_OFFSET_BITS=64
LOCAL_LDFLAGS = -lm
MBEDTLS_LIBS = $(MBEDTLS_LIB_DIR)/libmbedtls.a $(MBEDTLS_LIB_DIR)/libmbedx509.a $(MBEDTLS_LIB_DIR)/libmbedcrypto.a
MBEDTLS_CONFIG_INC = $(MBEDTLS_INC_DIR)/config.h
LIBEV_LIBS = $(LIBEV_LIB_DIR)/libev.a

ifdef DEBUG
LOCAL_CFLAGS += -g3
endif

COMPILE=$(QUIET_CC) $(CC) $(LOCAL_CFLAGS) $(CFLAGS)
LINK=$(QUIET_LINK) $(CC)

ifndef V
QUIET_CC   = @echo "  CC    $@" 1>&2;
QUIET_LINK = @echo "  LINK  $@" 1>&2;
endif

INDENT_SETTINGS = -br -brf -brs -ce -cli2 -di1 -i2 -l100 -nbad -ncs -npcs -nprs \
		  -npsl -nut -T session_context -T global_context -T ev_io -T ev_timer \
		  -T mbedtls_ssl_context
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	INDENT = gnuindent $(INDENT_SETTINGS)
else
	INDENT = indent $(INDENT_SETTINGS)
endif

APP = goldy
OBJS = goldy.o daemonize.o log.o

APP_CLIENT = goldy-client
APP_CLIENT_OBJS = goldy-client.o daemonize.o log.o

SEND_ONE_DTLS_PACKET = test/send_one_dtls_packet
SEND_ONE_DTLS_PACKET_OBJS = test/send_one_dtls_packet.o

TEST_CLIENT = test/dtls_test_client
TEST_CLIENT_OBJS = test/dtls_test_client.o

TEST_SERVER = test/udp_test_server
TEST_SERVER_OBJS = test/udp_test_server.o

TEST_APPS = $(SEND_ONE_DTLS_PACKET) $(TEST_CLIENT) $(TEST_SERVER)
TEST_OBJS = $(SEND_ONE_DTLS_PACKET_OBJS) $(TEST_CLIENT_OBJS) $(TEST_SERVER_OBJS)

SRCS_C = $(OBJS:.o=.c) $(APP_CLIENT_OBJS:.o=.c) $(TEST_CLIENT_OBJS:.o=.c) $(TEST_SERVER_OBJS:.o=.c)
SRCS_H = $(OBJS:.o=.h)

GEN_KEY = $(MBEDTLS_PROG_DIR)/mbedtls_gen_key
CERT_WRITE = $(MBEDTLS_PROG_DIR)/mbedtls_cert_write

.PHONY: all clean distclean deps test format

all: $(APP) $(APP_CLIENT)

$(APP): $(OBJS) $(MBEDTLS_LIBS) $(LIBEV_LIBS)
	$(LINK) -o $@ $^ $(LOCAL_LDFLAGS) $(LDFLAGS)

$(APP_CLIENT): $(APP_CLIENT_OBJS) $(MBEDTLS_LIBS) $(LIBEV_LIBS)
	$(LINK) -o $@ $^ $(LOCAL_LDFLAGS) $(LDFLAGS)

$(SEND_ONE_DTLS_PACKET): $(SEND_ONE_DTLS_PACKET_OBJS) $(MBEDTLS_LIBS)
	$(LINK) -o $@ $^ $(LOCAL_LDFLAGS) $(LDFLAGS)

$(TEST_CLIENT): $(TEST_CLIENT_OBJS) $(MBEDTLS_LIBS)
	$(LINK) -o $@ $^ $(LOCAL_LDFLAGS) $(LDFLAGS)

$(TEST_SERVER): $(TEST_SERVER_OBJS) $(LIBEV_LIBS)
	$(LINK) -o $@ $^ $(LOCAL_LDFLAGS) $(LDFLAGS)

%.o: %.c $(MBEDTLS_CONFIG_INC)
	$(COMPILE) -o $@ -c $<

$(MBEDTLS_CONFIG_INC):
	@echo ""
	@echo "mbed TLS include files not found in $(MBEDTLS_INC_DIR); run:"
	@echo ""
	@echo "    make deps"
	@echo ""
	@echo "to download and build mbed TLS."
	@echo ""
	@false

clean:
	rm -f $(APP) $(APP_CLIENT) $(OBJS) $(APP_CLIENT_OBJS) $(TEST_APPS) $(TEST_OBJS)

distclean: clean
	$(MAKE) -C deps distclean

deps:
	$(MAKE) -C deps download_deps build_deps

test: $(APP) $(TEST_APPS) test/keys/test-proxy-key.pem test/keys/test-proxy-cert.pem
	test/run_test.sh

$(GEN_KEY):
	$(MAKE) -C $(MBEDTLS_PROG_DIR) pkey/gen_key

test/keys/test-proxy-key.pem: $(GEN_KEY)
	$(GEN_KEY) type=ec ec_curve=secp256r1 format=pem filename=$@

$(CERT_WRITE):
	$(MAKE) -C $(MBEDTLS_PROG_DIR) x509/cert_write

test/keys/test-proxy-cert.pem: test/keys/test-proxy-key.pem $(CERT_WRITE)
	$(CERT_WRITE) issuer_name="CN=goldy.local, O=Dummy Ltd, C=US" \
		selfsign=1 issuer_key=$< output_file=$@

format:
	$(INDENT) $(SRCS_C) $(SRCS_H)
