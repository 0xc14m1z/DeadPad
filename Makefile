CC := clang
CFLAGS := -Wall -Wextra -Wpedantic -O2 -fobjc-arc
CLI_FRAMEWORKS := -framework Foundation -framework ApplicationServices
APP_FRAMEWORKS := -framework Cocoa -framework ApplicationServices

PREFIX ?= /usr/local
APP_NAME := DeadPad
APP_BUNDLE := $(APP_NAME).app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS
APP_RESOURCES := $(APP_CONTENTS)/Resources
APP_EXEC := $(APP_MACOS)/$(APP_NAME)
APP_HELPER := $(APP_RESOURCES)/deadpad
APP_PLIST := $(APP_CONTENTS)/Info.plist

.PHONY: all app cli clean install

all: cli app

cli: deadpad

app: $(APP_EXEC) $(APP_HELPER) $(APP_PLIST)

deadpad: src/deadpad.m
	$(CC) $(CFLAGS) -o $@ $< $(CLI_FRAMEWORKS)

$(APP_EXEC): src/DeadPadApp.m | $(APP_MACOS)
	$(CC) $(CFLAGS) -o $@ $< $(APP_FRAMEWORKS)

$(APP_HELPER): deadpad | $(APP_RESOURCES)
	install -m 755 deadpad $@

$(APP_PLIST): app/Info.plist | $(APP_CONTENTS)
	cp app/Info.plist $@

$(APP_CONTENTS) $(APP_MACOS) $(APP_RESOURCES):
	mkdir -p $@

install: deadpad
	install -d "$(PREFIX)/bin"
	install -m 755 deadpad "$(PREFIX)/bin/deadpad"

clean:
	rm -rf deadpad $(APP_BUNDLE)
