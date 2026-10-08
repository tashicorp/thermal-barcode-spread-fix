PREFIX ?= $(HOME)/.local

bin/print-label: Sources/print-label.swift
	@mkdir -p bin
	swiftc -O -o $@ $<

test: bin/print-label
	Tests/run.sh

install: bin/print-label
	install -d $(PREFIX)/bin
	install -m 755 bin/print-label $(PREFIX)/bin/print-label

# Print Label.app: Finder right-click > Print Label, or Open With (uses the default printer)
APP = build/Print Label.app
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

app: bin/print-label MacApp/PrintLabelApp.swift MacApp/Info.plist
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	swiftc -O -o "$(APP)/Contents/MacOS/PrintLabel" MacApp/PrintLabelApp.swift
	cp MacApp/Info.plist "$(APP)/Contents/Info.plist"
	cp bin/print-label "$(APP)/Contents/Resources/print-label"
	codesign --force --sign - "$(APP)/Contents/Resources/print-label"
	codesign --force --sign - "$(APP)"

install-app: app
	rm -rf "/Applications/Print Label.app"
	cp -R "$(APP)" /Applications/
	$(LSREGISTER) -f "/Applications/Print Label.app"
	/System/Library/CoreServices/pbs -update

clean:
	rm -rf bin build Tests/out

.PHONY: test install app install-app clean
