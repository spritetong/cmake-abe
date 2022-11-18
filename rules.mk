# * @file       rules.mk
# * @brief      This file contains common rules to build cmake targets.
# * @details    Copyright (C) 2022 spritetong@gmail.com.\n
# *             All rights reserved.\n
# * @author     spritetong@gmail.com
# * @date       2014
# * @version    1.0, 7/9/2022, Tong
# *             - Initial revision.
# *

ifndef __RULES_MK__
__RULES_MK__ = $(abspath $(lastword $(MAKEFILE_LIST)))
ifeq ($(CMKABE_HOME),)
    include $(dir $(__RULES_MK__))env.mk
endif
include $(CMKABE_HOME)/targets.mk

ifndef WORKSPACE_DIR
    #! Insert to the head of Makefile in the workspace directory:
    #!    WORKSPACE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
    $(error WORKSPACE_DIR is not defined)
endif

# ==============================================================================
# = CMake

override DEBUG := $(call bool,$(DEBUG),ON)
override VERBOSE := $(call bool,$(VERBOSE),OFF)

#! The current configuration of CMake build.
CMAKE_BUILD_TYPE ?= $(call bsel,$(DEBUG),Debug,Release)
#! The root of CMake build directories.
CMAKE_BUILD_ROOT ?= $(WORKSPACE_DIR)/target/cmake
#! The CMake build directory for the current configuration.
CMAKE_BUILD_DIR ?= $(CMAKE_BUILD_ROOT)/$(TARGET_TRIPLE)/$(CMAKE_BUILD_TYPE)
#! CMake output directories to clean.
CMAKE_OUTPUT_DIRS +=
#! CMake output file patterns to clean.
CMAKE_OUTPUT_FILE_PATTERNS += *.o *.obj *.a *.so *.so.* *.out *.lib *.dll *.exp *.exe *.pdb *.bin *.hex

CMAKE_INIT = cmake -B "$(CMAKE_BUILD_DIR)"
CMAKE_INIT += $(if $(MSVC_ARCH),-A $(MSVC_ARCH),)
CMAKE_INIT += -D "TARGET:STRING=$(TARGET)" -D "TARGET_TRIPLE:STRING=$(TARGET_TRIPLE)"
CMAKE_INIT += -D "CMAKE_BUILD_TYPE:STRING=$(CMAKE_BUILD_TYPE)"
CMAKE_INIT += -D "CMAKE_VERBOSE_MAKEFILE:BOOL=$(VERBOSE)"
CMAKE_INIT += $(foreach I,$(CMAKE_DEFS), -D$I)

# FIXME: repeat 3 times to work around the cache problem of cross compilation on Linux.
cmake_init = $(CMAKE_INIT)$(foreach I,1 2, && $(CMAKE_INIT) >$(NULL) 2>&1)
cmake_build = cmake --build "$(CMAKE_BUILD_DIR)" --config $(CMAKE_BUILD_TYPE) --parallel $(CMAKE_OPTS)
cmake_install = cmake --install "$(CMAKE_BUILD_DIR)" --config $(CMAKE_BUILD_TYPE) $(CMAKE_OPTS)
cmake_clean = $(call cmake_build) --target clean

# ==============================================================================
# = Cargo

#! Cargo toolchain
CARGO_TOOLCHAIN +=
#! Extra options passed to "cargo build" or "cargo run"
CARGO_OPTS += $(if $(filter $(TARGET_TRIPLE),$(HOST_TRIPLE)),,--target $(TARGET_TRIPLE))
CARGO_OPTS += $(call bsel,$(DEBUG),,--release)
#! Cargo binary crates
CARGO_EXECUTABLES +=
#! Cargo library crates
CARGO_LIBRARIES +=

# cargo_run(<crate:str>,<options:str>)
cargo_run = cargo $(CARGO_TOOLCHAIN) run --bin $(1) $(CARGO_OPTS) $(2)

# cargo_build(<crate:str>,<options:str>)
cargo_build = cargo $(CARGO_TOOLCHAIN) build --bin $(1) $(CARGO_OPTS) $(2)

# cargo_build_lib(<options:str>)
cargo_build_lib = cargo $(CARGO_TOOLCHAIN) build --lib $(CARGO_OPTS) $(1)

# cargo_test(<options:str>)
cargo_test = cargo $(CARGO_TOOLCHAIN) test $(CARGO_OPTS) $(1)

# cargo_upgrade(<excludes:str>,<options:str>)
cargo_upgrade = cargo upgrade --incompatible $(1)

# Set crosss compile tools for Rust
# cargo_set_gcc_env_vars()
cargo_set_gcc_env_vars = $(eval $(_cargo_set_gcc_env_vars_tpl_))
define _cargo_set_gcc_env_vars_tpl_
    export CARGO_TARGET_$$(call upper,$$(subst -,_,$$(TARGET_TRIPLE)))_LINKER=$$(TARGET)-gcc
    $$(foreach I,AR=ar CC=gcc CXX=g++ LD=ld RANLIB=ranlib STRIP=strip,\
        $$(eval export $$(call kv_key,$$I)_$$(subst -,_,$$(TARGET_TRIPLE))=$$(TARGET)-$$(call kv_value,$$I)))
endef

# If a cross compile GCC exists, set the appropriate environment variables for Rust.
ifeq ($(shell $(TARGET)-gcc -dumpversion >$(NULL) 2>&1 || echo 1),)
    $(call cargo_set_gcc_env_vars)
endif
export CARGO_WORKSPACE_DIR = $(WORKSPACE_DIR)

# ==============================================================================
# = Rules

_saved_default_goal := $(.DEFAULT_GOAL)

.PHONY: cmake cmake-init cmake-build cmake-rebuild cmake-install \
        cmake-clean cmake-distclean cmake-clean-root cmake-clean-outputs \
        cargo-lib cargo-clean cargo-upgrade

cmake: cmake-build

# Initialize the cmake build directory.
cmake-init $(CMAKE_BUILD_DIR):
	@$(call cmake_init)

# Build the target 
cmake-build: $(CMAKE_BUILD_DIR)
	@$(call cmake_build)

# Clean the target and rebuild it.
cmake-rebuild: cmake-clean cmake-build

# Install the target.
cmake-install: cmake-build
	@$(call cmake_install)

# Clean the target.
cmake-clean: cmake-clean-outputs
	@$(call exists,"$(CMAKE_BUILD_DIR)") && $(call cmake_clean) || $(OK)

# Clean the target and erase the build directory.
cmake-distclean: cmake-clean-outputs
	@$(RM) -r -f "$(CMAKE_BUILD_DIR)" || $(OK)

# Clean the root directory of all targets.
cmake-clean-root: cmake-clean-outputs
	@$(RM) -r -f "$(CMAKE_BUILD_ROOT)" || $(OK)

# Clean extra output files.
cmake-clean-outputs:
	@$(if $(CMAKE_OUTPUT_DIRS),$(call git_remove_ignored,$(CMAKE_OUTPUT_DIRS),$(CMAKE_OUTPUT_FILE_PATTERNS)) || $(OK),$(OK))
	@$(call exists,"$(WORKSPACE_DIR)/CMakeLists.txt") && $(TOUCH) "$(WORKSPACE_DIR)/CMakeLists.txt" || $(OK)

# Build all Rust libraries
cargo-lib:
	@$(call cargo_build_lib)

# Cargo test.
cargo-test:
	@$(call cargo_test)

# Clean all Cargo targets.
cargo-clean:
	-@cargo clean

# Upgrade dependencies
cargo-upgrade:
	@cargo update
	@$(call cargo_upgrade)

# Do not change the default goal.
.DEFAULT_GOAL := $(_saved_default_goal)
undefine _saved_default_goal

# Generate common rules for Cargo and CMake.
rules_for_cargo_cmake = $(eval $(_rules_for_cargo_cmake_tpl_))
define _rules_for_cargo_cmake_tpl_
    ifeq ($$(BIN),)
        BIN = $$(call kv_value,$$(firstword $$(CARGO_EXECUTABLES)))
    else
        override BIN := $$(call sel,$$(BIN),$$(CARGO_EXECUTABLES),$$(BIN))
    endif

    .PHONY: build
    build:
		@$$(call cargo_build,$$(BIN)) || echo ***Please specify the binary name by "BIN=<name>"

    .PHONY: run
    run:
		@$$(call cargo_run,$$(BIN))

    .PHONY: lib
    lib: cargo-lib

    .PHONY: clean
    clean: cargo-clean cmake-clean-outputs

    .PHONY: clean-cmake
    clean-cmake: cmake-clean-root

    .PHONY: upgrade
    upgrade: cargo-upgrade

    .PHONY: help
    help:
		@$(call less,"$(CMKABE_HOME)/usage.txt")

    $$(foreach I,$$(CARGO_EXECUTABLES),\
        $$(eval $$(call _cargo_build_tpl_,$$(call kv_key,$$I),$$(call kv_value,$$I))))

    $$(foreach I,$$(CARGO_EXECUTABLES),\
        $$(eval $$(call _cargo_run_tpl_,$$(call kv_key,$$I),$$(call kv_value,$$I))))

    $$(foreach I,$$(CARGO_LIBRARIES),\
        $$(eval $$(call _cargo_build_lib_tpl_,$$(call kv_key,$$I),$$(call kv_value,$$I))))
endef
define _cargo_build_tpl_
    ifneq ($(1),$(2))
        .PHONY: $(1)
        $(1): $(2)
    endif
    .PHONY: $(2)
    $(2):
		@$$(call cargo_build,$(2))
endef
define _cargo_run_tpl_
    ifneq ($(1),$(2))
        .PHONY: run-$(1)
        run-$(1): run-$(2)
    endif
    .PHONY: run-$(2)
    run-$(2):
		@$$(call cargo_run,$(2))
endef
define _cargo_build_lib_tpl_
    ifneq ($(1),$(2))
        .PHONY: $(1)
        $(1): $(2)
    endif
    .PHONY: $(2)
    $(2):
		@$$(call cargo_build_lib,-p $(2))
endef

endif # __RULES_MK__
