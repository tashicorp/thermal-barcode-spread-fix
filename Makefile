PREFIX ?= $(HOME)/.local

bin/print-label: Sources/print-label.swift
	@mkdir -p bin
	swiftc -O -o $@ $<

test: bin/print-label
	Tests/run.sh

install: bin/print-label
	install -d $(PREFIX)/bin
	install -m 755 bin/print-label $(PREFIX)/bin/print-label

# Print Label.app: Finder right-click > Open With > Print Label (uses the default printer)
APP = /Applications/Print Label.app
install-app: install
	rm -rf "$(APP)"
	osacompile -o "$(APP)" "MacApp/Print Label.applescript"
	plutil -replace CFBundleIdentifier -string com.github.tashicorp.thermal-barcode-spread-fix.print-label "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleDocumentTypes -json '[{"CFBundleTypeName":"PDF document","CFBundleTypeRole":"Viewer","LSHandlerRank":"Alternate","LSItemContentTypes":["com.adobe.pdf"]}]' "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(APP)"

clean:
	rm -rf bin Tests/out

.PHONY: test install install-app clean
