# Halo — build harness
#
# Targets:
#   make build       Compile in debug
#   make test        Run unit tests
#   make icon        Rebuild Halo.icns from CoreGraphics renderer
#   make app         Produce dist/Halo.app (release, ad-hoc OR Developer ID)
#   make install     Copy Halo.app into /Applications
#   make run         Launch the assembled bundle
#   make clean       Remove .build and dist
#   make dist        Produce dist/Halo-vX.Y.Z.zip ready for sharing (+ sha256)
#   make release     Full pipeline: app + notarize + staple + zip + sha256
#                    (requires HALO_SIGNING_IDENTITY env var + notarytool profile)

SWIFT       ?= swift
APP_NAME    := Halo
DIST_APP    := dist/$(APP_NAME).app
ICONSET     := Resources/$(APP_NAME).iconset
ICNS        := Resources/$(APP_NAME).icns
VERSION     := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist 2>/dev/null)

.PHONY: build test icon app install run clean dist release notarize

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
	@cd dist && shasum -a 256 Halo-v$(VERSION).zip | tee Halo-v$(VERSION).zip.sha256
	@ls -lh dist/Halo-v$(VERSION).zip | awk '{print "    " $$5 "  " $$9}'

# Notarize a Developer-ID-signed dist/Halo.app and staple the ticket.
# Prerequisite: `xcrun notarytool store-credentials halo-notary` and a
# Developer ID Application certificate in the keychain.
notarize:
	@[ -d "$(DIST_APP)" ] || { echo "error: $(DIST_APP) missing — run \`HALO_SIGNING_IDENTITY=... make app\` first" >&2; exit 1; }
	bash scripts/notarize.sh

# End-to-end release: requires a Developer ID identity + notarytool profile.
# Produces dist/Halo-vX.Y.Z.zip + .sha256 stapled and Gatekeeper-clean.
release:
	@if [ -z "$(HALO_SIGNING_IDENTITY)" ]; then \
		echo "error: HALO_SIGNING_IDENTITY env var unset. See docs/RELEASE.md." >&2; \
		exit 1; \
	fi
	$(MAKE) clean
	$(MAKE) test
	$(MAKE) app
	$(MAKE) notarize
