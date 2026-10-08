PREFIX ?= $(HOME)/.local

bin/print-label: Sources/print-label.swift
	@mkdir -p bin
	swiftc -O -o $@ $<

test: bin/print-label
	Tests/run.sh

install: bin/print-label
	install -d $(PREFIX)/bin
	install -m 755 bin/print-label $(PREFIX)/bin/print-label

# Finder right-click > Quick Actions > Print Label (uses the default printer)
install-quick-action: install
	install -d $(HOME)/Library/Services
	rm -rf "$(HOME)/Library/Services/Print Label.workflow"
	cp -R "QuickAction/Print Label.workflow" $(HOME)/Library/Services/
	/System/Library/CoreServices/pbs -update

clean:
	rm -rf bin Tests/out

.PHONY: test install install-quick-action clean
