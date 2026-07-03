SWIFTC := swiftc
ARCH ?= $(shell uname -m)
MACOSX_DEPLOYMENT_TARGET ?= 12.0
SWIFTFLAGS := -O -parse-as-library -target $(ARCH)-apple-macos$(MACOSX_DEPLOYMENT_TARGET)
HELPER_SWIFTFLAGS := $(SWIFTFLAGS) -import-objc-header src/DeadPadCoreTypes.h
HELPER_FRAMEWORKS := -framework Foundation -framework ApplicationServices
APP_SWIFTFLAGS := $(SWIFTFLAGS)
APP_FRAMEWORKS := -framework Cocoa

APP_NAME := DeadPad
APP_BUNDLE := $(APP_NAME).app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS
APP_RESOURCES := $(APP_CONTENTS)/Resources
APP_EXEC := $(APP_MACOS)/$(APP_NAME)
APP_HELPER := $(APP_RESOURCES)/deadpad
APP_PLIST := $(APP_CONTENTS)/Info.plist

.PHONY: all app clean

all: app

app: $(APP_EXEC) $(APP_HELPER) $(APP_PLIST)

$(APP_EXEC): src/DeadPadApp.swift | $(APP_MACOS)
	$(SWIFTC) $(APP_SWIFTFLAGS) -o $@ $< $(APP_FRAMEWORKS)

$(APP_HELPER): src/deadpad.swift src/DeadPadCoreTypes.h | $(APP_RESOURCES)
	$(SWIFTC) $(HELPER_SWIFTFLAGS) -o $@ src/deadpad.swift $(HELPER_FRAMEWORKS)

$(APP_PLIST): app/Info.plist | $(APP_CONTENTS)
	cp app/Info.plist $@

$(APP_CONTENTS) $(APP_MACOS) $(APP_RESOURCES):
	mkdir -p $@

clean:
	rm -rf deadpad $(APP_BUNDLE)
