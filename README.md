# thermal-barcode-spread-fix

Makes dense 1D barcodes scannable on thermal printers whose dots spread, such as portable A4 printers and budget label printers, **without scaling the label**.

The command is `print-label`. macOS only. One Swift file, no dependencies.

**Do you need this?** Probably not if you have a proper label printer (Zebra, Dymo …) and your labels already scan. Run `print-label calibrate`: if gaps of 1–2 dots stay white, your printer doesn't spread enough to need it.

## The problem

Carrier labels, such as Australia Post MyPost Business 4×6 labels, use dense Code 128 barcodes. On a MyPost label the narrowest bar or gap is 0.84pt, which is about **2.4 dots** at 203 dpi. Good label printers print this fine. But some thermal printers spread each dot far enough that 1–2 dot gaps fill in completely: the bars merge and the barcode won't scan. This is common with printers built for documents rather than labels, plain thermal paper, and drivers with no print-width adjustment.

Things that don't fix it:

- **Scaling the label up.** The barcode scans, but carriers ask you not to scale labels. Australia Post: *"make sure you're not scaling the PDF when printing."*
- **Lowering print darkness alone.** On the printer this was tested on, it wasn't enough.

## What print-label does

1. Renders the PDF itself at your printer's exact resolution, with smoothing off, so the driver doesn't resample it.
2. Finds every 1D barcode using Apple's built-in barcode reader (Vision), and thins each bar by `N` dots. The leading edges, spacing and overall size don't change, so the data and printed size are the same. 2D codes (QR, DataMatrix, PDF417 …) and text aren't touched.
3. Turns the page 90° if a barcode's bars lie across the paper, which is how they sit on a MyPost 4×6 label. Rows of dense bars across the print head build up heat and fill the gaps in. Bars that run along the paper feed don't. Use `--no-rotate` to turn this off.
4. Simulates the print head spreading every bar back by `N` dots, and decodes every barcode on the page from that. **If any value differs from the original, it refuses to print.**
5. Sends the result at 100% scale, at the PDF's own page size, swapping width and height if the page was turned.

This is the same "bar-width reduction" that professional label software applies for thermal printers.

## Install

```sh
git clone <this repo> && cd thermal-barcode-spread-fix
make install          # builds with swiftc, installs to ~/.local/bin/print-label
```

Requires the Xcode command line tools (`xcode-select --install`).

### Print Label app (optional)

```sh
make install-app
```

Installs `/Applications/Print Label.app`, which adds **Print Label** to Finder's right-click menu for PDFs. It also works from Open With, or open the app and pick a file. It runs its bundled copy of `print-label` on the default printer with that printer's default settings, then shows a notification, or an alert if the barcode couldn't be verified. Each run is logged to `~/Library/Logs/PrintLabel.log`.

Set your thermal printer as the default and its darkness default first:

```sh
lpoptions -d QUEUE
lpadmin -p QUEUE -o Darkness-default=Low   # option name depends on the driver
```

If the menu item doesn't appear, run `killall Finder`, or look under right-click → Services. To test without printing, run `"/Applications/Print Label.app/Contents/MacOS/PrintLabel" --dry-run label.pdf`.

## Use

```sh
print-label calibrate --printer MY_QUEUE           # print a gap test sheet (4×6)
print-label --printer MY_QUEUE label.pdf           # print a label
print-label --out fixed.pdf label.pdf              # write the processed PDF instead
```

List queue names with `lpstat -p`. Run `print-label --help` for every option:

| Option | Default | |
|---|---|---|
| `--printer QUEUE` | system default printer | CUPS queue |
| `--dpi N` | from the queue's driver, else 203 | printer resolution |
| `--reduce N` | 1 | dots to thin each bar |
| `-o key=value` | none | passed to `lp`, e.g. `-o Darkness=Low` (option names depend on the driver: `lpoptions -p QUEUE -l`) |
| `--page-size SIZE` | `Custom.WxH` from the PDF | `lp` PageSize |
| `--no-rotate` | off | don't turn pages so bars run along the feed |
| `--out FILE.pdf` | none | don't print, write the result |

### Calibrating

`print-label calibrate` prints rows of 6-dot bars with gaps of 1 to 8 dots, in both directions. Find the smallest `N` where the gaps stay white in both directions. As a starting point, use `--reduce` = `N − 3`:

- `N` of 3 or less: 0
- `N` = 4: 1
- `N` = 5: 2

If bars still merge, raise it. If thin bars break up, lower it. This rule comes from one printer, so treat it as a starting point, not a measurement.

Also lower the driver's darkness or density if it has one. On the tested printer, darkness and thinning were both needed.

## Tested

| Printer | dpi | Settings that scanned | Notes |
|---|---|---|---|
| Netum LT-P10 (A4 portable) | 203 | `-o Darkness=Low --reduce 1`, rotated | Each of these alone didn't scan: plain PDF at Low; thinning at Medium; thinning at Low without rotation. Set `zeMediaTracking=RollPaper` for roll paper, or each print feeds about 30cm. |

Please open a PR adding your printer to this table.

## Limits

- The check uses Apple's barcode reader on a simulated print, not a carrier's scanner. Before relying on it, test one label: scan the printed barcode with a phone barcode app and compare the number.
- The simulated print is only a model of the print head. It catches lost or merged bars, but can't prove your printer will spread the bars exactly `N` dots.
- PDFs with rotated pages (`/Rotate`) aren't supported yet.
- At 200/203 dpi each bar can only be a whole number of dots, so widths vary by ±1 dot. Code 128 tolerates this.
- Only Code 128 has been tested. Other 1D types (Code 39, EAN/UPC, ITF …) are processed the same way and should work, but are untested. GS1 DataBar may react differently to thinning.
- If you print many labels, a dedicated label printer whose barcodes scan without help is the real fix.

## Tests

```sh
make test
```

Builds a synthetic label with made-up data, then processes it at `--reduce` 0, 1 and 2:

- At every level, print-label must verify all barcodes. The label has one barcode in each direction plus a QR code.
- At 1 and 2, both barcode directions must be detected and thinned.
- At 0, the output must also decode independently.

Real labels contain names and addresses, so don't commit them. `.gitignore` blocks PDFs and images outside `Tests/fixtures`.

## License

MIT
