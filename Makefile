# Halo — build harness
#
# Targets:
#   make build     Compile in debug
#   make test      Run unit tests
#   make icon      Rebuild Halo.icns from CoreGraphics renderer
#   make app       Produce dist/Halo.app (release, ad-hoc signed)
#   make install   Copy Halo.app into /Applications
#   make run       Launch the assembled bundle
#   make clean     Remove .build and dist
#   make dist      Produce dist/Halo-vX.Y.Z.zip ready for sharing

SWIFT       ?= swift
APP_NAME    := Halo
DIST_APP    := dist/$(APP_NAME).app
ICONSET     := Resources/$(APP_NAME).iconset
ICNS        := Resources/$(APP_NAME).icns
VERSION     := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist 2>/dev/null)

.PHONY: build test icon app install run clean dist

build:
	$(SWIFT) build

test:
	$(SWIFT) test

icon:
	$(SWIFT) scripts/render-icon.swift $(ICONSET)
	iconutil -c icns $(ICONSET) -o $(ICNS)

app: $(ICNS)
	bash scripts/build-app.sh

$(ICNS):
	$(MAKE) icon

install: app
	@if [ -d "/Applications/$(APP_NAME).app" ]; then \
		echo "==> removing previous /Applications/$(APP_NAME).app"; \
		rm -rf "/Applications/$(APP_NAME).app"; \
	fi
	cp -R $(DIST_APP) /Applications/
	@echo "==> installed: /Applications/$(APP_NAME).app"
	@echo "    open /Applications/$(APP_NAME).app   to launch"

run: app
	open $(DIST_APP)

clean:
	rm -rf .build dist

dist: app
	@echo "==> packaging Halo-v$(VERSION).zip"
	cd dist && ditto -c -k --sequesterRsrc --keepParent $(APP_NAME).app Halo-v$(VERSION).zip
	@ls -lh dist/Halo-v$(VERSION).zip | awk '{print "    " $$5 "  " $$9}'
