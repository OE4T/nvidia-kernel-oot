# SPDX-FileCopyrightText: Copyright (c) 2023-2024 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

KERNEL_HEADERS ?= /lib/modules/$(shell uname -r)/build
KERNEL_OUTPUT ?= ${KERNEL_HEADERS}

MAKEFILE_DIR := $(abspath $(shell dirname $(lastword $(MAKEFILE_LIST))))
NVIDIA_CONFTEST ?= $(MAKEFILE_DIR)/out/nvidia-conftest
HOSTCC ?= gcc
MODLIB ?= /lib/modules
CC ?= $(CROSS_COMPILE)gcc
CXX ?= $(CROSS_COMPILE)g++
LD ?= $(CROSS_COMPILE)ld.bfd
AR ?= $(CROSS_COMPILE)ar
OBJCOPY ?= $(CROSS_COMPILE)objcopy

V ?= 0

ifneq ($(words $(subst :, ,$(MAKEFILE_DIR))), 1)
$(error source directory cannot contain spaces or colons)
endif

.PHONY : help modules modules_install clean conftest nvidia-headers hwpm nvidia-oot nvgpu

# help is default target!
help:
	@echo   "================================================================================"
	@echo   "Usage:"
	@echo   "   make modules          # to build NVIDIA OOT and display drivers"
	@echo   "   make dtbs             # to build NVIDIA DTBs"
	@echo   "   make modules_install  # to install drivers to the INSTALL_MOD_PATH"
	@echo   "   make clean            # to make clean driver sources"
	@echo   "================================================================================"

modules: hwpm nvidia-oot nvgpu nvidia-display
dtbs: nvidia-dtbs
modules_install: hwpm nvidia-oot nvgpu nvidia-display-install
clean: hwpm nvidia-oot nvgpu nvidia-display-clean nvidia-dtbs-clean

$(NVIDIA_CONFTEST):
	mkdir -p $@

conftest:
ifeq ($(MAKECMDGOALS), modules)
	@echo   "================================================================================"
	@echo   "make $(MAKECMDGOALS) - conftest ..."
	@echo   "================================================================================"
	mkdir -p $(NVIDIA_CONFTEST)/nvidia;
	cp -av $(MAKEFILE_DIR)/nvidia-oot/scripts/conftest/* $(NVIDIA_CONFTEST)/nvidia/
	$(MAKE) ARCH=arm64 \
		src=$(NVIDIA_CONFTEST)/nvidia obj=$(NVIDIA_CONFTEST)/nvidia \
		CC="$(CC)" LD="$(LD)" \
		NV_KERNEL_SOURCES=$(KERNEL_SRC) \
		NV_KERNEL_OUTPUT=$(KBUILD_OUTPUT) \
		-f $(NVIDIA_CONFTEST)/nvidia/Makefile
endif

hwpm: conftest
	@if [ ! -d "$(MAKEFILE_DIR)/hwpm" ] ; then \
		echo "Directory hwpm is not found, exiting.."; \
		false; \
	fi
	@echo   "================================================================================"
	@echo   "make $(MAKECMDGOALS) - hwpm ..."
	@echo   "================================================================================"
	$(MAKE) ARCH=arm64 \
		-C $(KERNEL_PATH) \
		M=$(MAKEFILE_DIR)/hwpm/drivers/tegra/hwpm \
		MODLIB=$(MODLIB) \
		CONFIG_TEGRA_OOT_MODULE=m \
		srctree.hwpm=$(MAKEFILE_DIR)/hwpm \
		srctree.nvconftest=$(NVIDIA_CONFTEST) \
		$(MAKECMDGOALS)

nvidia-oot: conftest hwpm
	@if [ ! -d "$(MAKEFILE_DIR)/nvidia-oot" ] ; then \
		echo "Directory nvidia-oot is not found, exiting.."; \
		false; \
	fi
	@echo   "================================================================================"
	@echo   "make $(MAKECMDGOALS) - nvidia-oot ..."
	@echo   "================================================================================"
	$(MAKE) ARCH=arm64 \
		-C $(KERNEL_PATH) \
		M=$(MAKEFILE_DIR)/nvidia-oot \
		MODLIB=$(MODLIB) \
		CONFIG_TEGRA_OOT_MODULE=m \
		KCFLAGS="-Wno-error=address" \
		srctree.nvidia-oot=$(MAKEFILE_DIR)/nvidia-oot \
		srctree.hwpm=$(MAKEFILE_DIR)/hwpm \
		srctree.nvconftest=$(NVIDIA_CONFTEST) \
		KBUILD_EXTRA_SYMBOLS=$(MAKEFILE_DIR)/hwpm/drivers/tegra/hwpm/Module.symvers \
		$(MAKECMDGOALS)

nvgpu: conftest nvidia-oot
	if [ ! -d "$(MAKEFILE_DIR)/nvgpu" ] ; then \
		echo "Directory nvgpu is not found, exiting.."; \
		false; \
	fi
	@echo   "================================================================================"
	@echo   "make $(MAKECMDGOALS) - nvgpu ..."
	@echo   "================================================================================"
	$(MAKE) ARCH=arm64 \
		-C $(KERNEL_PATH) \
		M=$(MAKEFILE_DIR)/nvgpu/drivers/gpu/nvgpu \
		MODLIB=$(MODLIB) \
		CONFIG_TEGRA_OOT_MODULE=m \
		srctree.nvidia=$(MAKEFILE_DIR)/nvidia-oot \
		srctree.nvidia-oot=$(MAKEFILE_DIR)/nvidia-oot \
		srctree.nvconftest=$(NVIDIA_CONFTEST) \
		KBUILD_EXTRA_SYMBOLS=$(MAKEFILE_DIR)/nvidia-oot/Module.symvers \
		$(MAKECMDGOALS)


define display-cmd
	$(MAKE) ARCH=arm64 TARGET_ARCH=aarch64 \
		-C $(MAKEFILE_DIR)/nvdisplay \
		NV_VERBOSE=$(V) \
		KERNELRELEASE="" \
		SYSSRC=$(KERNEL_SRC) \
		SYSOUT=$(KBUILD_OUTPUT) \
		OOTSRC=$(MAKEFILE_DIR)/nvidia-oot \
		KBUILD_EXTRA_SYMBOLS=$(MAKEFILE_DIR)/nvidia-oot/Module.symvers \
		SYSSRCHOST1X=$(MAKEFILE_DIR)/nvidia-oot/drivers/gpu/host1x/include \
		CC="$(CC)" \
		LD="$(LD)" \
		AR="$(AR)" \
		CXX="$(CXX)" \
		OBJCOPY="$(OBJCOPY)"
endef


nvidia-display: nvidia-oot
	@if [ ! -d "$(MAKEFILE_DIR)/nvdisplay" ] ; then \
		echo "Directory nvdisplay is not found, exiting.."; \
		false; \
	fi
	@echo   "================================================================================"
	@echo   "make $(MAKECMDGOALS) - nvidia-display ..."
	@echo   "================================================================================"
	$(display-cmd) modules
	@echo   "================================================================================"
	@echo   "Display driver compiled successfully."
	@echo   "================================================================================"


nvidia-display-install:
	@echo   "================================================================================"
	@echo   "make $(MAKECMDGOALS) - nvidia-display ..."
	@echo   "================================================================================"
	$(MAKE) -C $(KERNEL_PATH) \
		KERNEL_MODLIB=$(MODLIB) \
		M=$(MAKEFILE_DIR)/nvdisplay/kernel-open modules_install

nvidia-display-clean:
	@echo   "================================================================================"
	@echo   "make $(MAKECMDGOALS) - nvidia-display ..."
	@echo   "================================================================================"
	$(display-cmd) clean

nvidia-dtbs:
	@if [ ! -d "$(MAKEFILE_DIR)/kernel-devicetree" ] ; then \
		echo "Directory kernel-devicetree is not found, exiting.."; \
		false; \
	fi
	@echo   "================================================================================"
	@echo   "make nvidia-dtbs ..."
	@echo   "================================================================================"
	TEGRA_TOP=$(MAKEFILE_DIR) \
	srctree=$(KERNEL_SRC) \
	objtree=$(KBUILD_OUTPUT) \
	oottree=$(MAKEFILE_DIR)/kernel-devicetree \
	HOSTCC="$(HOSTCC)" \
	$(MAKE) -f $(MAKEFILE_DIR)/kernel-devicetree/scripts/Makefile.build \
		obj=$(MAKEFILE_DIR)/kernel-devicetree/generic-dts \
		dtbs
	@echo   "================================================================================"
	@echo   "DTBs compiled successfully."
	@echo   "================================================================================"

nvidia-dtbs-clean:
	@echo   "================================================================================"
	@echo   "make $(MAKECMDGOALS) - nvidia-dtbs ..."
	@echo   "================================================================================"
	rm -fr $(MAKEFILE_DIR)/kernel-devicetree/generic-dts/dtbs

