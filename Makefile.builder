ifneq (,$(findstring win,$(DIST)))
    WINDOWS_PLUGIN_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
    DISTRIBUTION := windows
    BUILDER_MAKEFILE = $(WINDOWS_PLUGIN_DIR)Makefile.windows
endif

# prevent windows-image-extract from failing
ifeq (dummy,$(DIST))
    DISTRIBUTION := dummy
    BUILDER_MAKEFILE = /dev/null
endif
