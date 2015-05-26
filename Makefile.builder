ifneq (,$(findstring win,$(DIST)))
    WINDOWS_PLUGIN_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
    DISTRIBUTION := windows
    BUILDER_MAKEFILE = $(FEDORA_PLUGIN_DIR)Makefile.windows
endif
