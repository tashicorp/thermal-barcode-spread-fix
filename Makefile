PREFIX ?= $(HOME)/.local

bin/print-label: Sources/print-label.swift
	@mkdir -p bin
	swiftc -O -o $@ $<

test: bin/print-label
	Tests/run.sh

install: bin/print-label
	install -d $(PREFIX)/bin
	install -m 755 bin/print-label $(PREFIX)/bin/print-label

clean:
	rm -rf bin Tests/out

.PHONY: test install clean
