#---------------------------------------------------------------------------------
# NEEDY GIRL OVERDOSE 3DS - homebrew port (.3dsx)
#---------------------------------------------------------------------------------
.SUFFIXES:

ifeq ($(strip $(DEVKITARM)),)
$(error "Please set DEVKITARM in your environment. export DEVKITARM=<path to>devkitARM")
endif

TOPDIR ?= $(CURDIR)
include $(DEVKITARM)/3ds_rules

TARGET      := needy3ds
BUILD       := build
SOURCES     := source source/lua
DATA        := data
INCLUDES    := source source/lua
GRAPHICS    :=
ROMFS       :=

APP_TITLE       := NEEDY GIRL OVERDOSE 3DS
APP_DESCRIPTION := Fan port (requires your own game data)
APP_AUTHOR      := port3ds

#---------------------------------------------------------------------------------
ARCH    := -march=armv6k -mtune=mpcore -mfloat-abi=hard -mtp=soft

CFLAGS  := -g -Wall -O2 -mword-relocations -ffunction-sections \
           $(ARCH) $(INCLUDE) -D__3DS__

CXXFLAGS := $(CFLAGS) -fno-rtti -fno-exceptions -std=gnu++11
ASFLAGS  := -g $(ARCH)
LDFLAGS   = -specs=3dsx.specs -g $(ARCH) -Wl,-Map,$(notdir $*.map)

LIBS    := -lcitro2d -lcitro3d -lvorbisidec -logg -lctru -lm
LIBDIRS := $(PORTLIBS) $(CTRULIB)

#---------------------------------------------------------------------------------
ifneq ($(BUILD),$(notdir $(CURDIR)))
#---------------------------------------------------------------------------------

export OUTPUT   := $(CURDIR)/$(TARGET)
export TOPDIR   := $(CURDIR)
export VPATH    := $(foreach dir,$(SOURCES),$(CURDIR)/$(dir)) $(foreach dir,$(DATA),$(CURDIR)/$(dir))
export DEPSDIR  := $(CURDIR)/$(BUILD)

CFILES   := $(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.c)))
SFILES   := $(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.s)))

export LD := $(CC)
export OFILES_SOURCES := $(CFILES:.c=.o) $(SFILES:.s=.o)
export OFILES := $(OFILES_SOURCES)
export INCLUDE := $(foreach dir,$(INCLUDES),-I$(CURDIR)/$(dir)) \
                  $(foreach dir,$(LIBDIRS),-I$(dir)/include) -I$(CURDIR)/$(BUILD)
export LIBPATHS := $(foreach dir,$(LIBDIRS),-L$(dir)/lib)

export APP_ICON := $(TOPDIR)/icon.png
export _3DSXFLAGS += --smdh=$(CURDIR)/$(TARGET).smdh

.PHONY: all clean

all: $(BUILD)
	@$(MAKE) --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile

$(BUILD):
	@mkdir -p $@

clean:
	@echo clean ...
	@rm -fr $(BUILD) $(TARGET).3dsx $(TARGET).smdh $(TARGET).elf

#---------------------------------------------------------------------------------
else
#---------------------------------------------------------------------------------

DEPENDS := $(OFILES:.o=.d)

$(OUTPUT).3dsx : $(OUTPUT).elf $(OUTPUT).smdh
$(OUTPUT).elf  : $(OFILES)

-include $(DEPENDS)

#---------------------------------------------------------------------------------
endif
