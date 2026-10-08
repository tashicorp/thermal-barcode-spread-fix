#!/bin/sh
# Processes a synthetic label at several --reduce values. print-label itself refuses to
# write output unless every barcode decodes (from a simulated print) to its original value.
# At --reduce 0 the output is also decoded independently. Thinned output isn't, because
# decoders misread the deliberately thin bars until the printer spreads them back.
set -eu
cd "$(dirname "$0")/.."
mkdir -p Tests/out
swift Tests/make-fixture.swift Tests/out/fixture.pdf
expected=$(swift Tests/decode.swift Tests/out/fixture.pdf)
count=$(printf '%s\n' "$expected" | grep -c .)
[ "$count" -eq 3 ] || { echo "FAIL: fixture should have 3 barcodes, found $count"; exit 1; }

status=0
for r in 0 1 2; do
  out=Tests/out/reduce-$r.pdf
  if ! log=$(bin/print-label --dpi 203 --reduce "$r" --out "$out" Tests/out/fixture.pdf 2>&1); then
    echo "FAIL reduce=$r: print-label refused"; echo "$log"; status=1; continue
  fi
  if [ "$r" -gt 0 ]; then
    thinned=$(printf '%s\n' "$log" | grep -c 'thinned')
    [ "$thinned" -eq 2 ] || { echo "FAIL reduce=$r: thinned $thinned barcodes, expected 2"; status=1; }
    printf '%s\n' "$log" | grep -q 'stacked along y' || { echo "FAIL reduce=$r: vertical stack not detected"; status=1; }
    printf '%s\n' "$log" | grep -q 'stacked along x' || { echo "FAIL reduce=$r: horizontal stack not detected"; status=1; }
  fi
  if [ "$r" -eq 0 ]; then
    got=$(swift Tests/decode.swift "$out")
    [ "$got" = "$expected" ] || {
      echo "FAIL reduce=0: decoded values differ"; echo "expected:"; echo "$expected"; echo "got:"; echo "$got"; status=1; continue; }
  fi
  echo "ok   reduce=$r"
done
exit $status
