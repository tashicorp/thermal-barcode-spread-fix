// print-label: print shipping-label PDFs on low-resolution (200/203 dpi) thermal printers
// at true size, with 1D barcodes that still scan.
//
// The PDF is rendered at the printer's own resolution with no smoothing, then every bar of
// every 1D barcode is thinned by N dots (bar-width reduction) to offset thermal dot spread.
// Bar centres and pitch are unchanged, so the barcode's data and printed size stay the same.
// Pages are turned so barcode bars run along the paper feed, which keeps gaps from filling in.
// Every barcode is decoded again after processing; if any value changed, nothing is printed.
import Foundation
import CoreGraphics
import CoreText
import Vision

let usage = """
usage: print-label [options] label.pdf
       print-label calibrate [options]

options:
  --printer QUEUE     CUPS queue (default: system default printer)
  --dpi N             printer resolution (default: from the queue's driver, else 203)
  --reduce N          dots to thin each barcode bar (default: 1)
  -o key=value        driver option passed to lp, repeatable (e.g. -o Darkness=Low)
  --page-size SIZE    lp PageSize (default: Custom.<width>x<height> from the PDF)
  --no-rotate         don't turn pages so barcode bars run along the paper feed
  --out FILE.pdf      write the processed PDF instead of printing
"""

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

// MARK: - Arguments

var input: String?
var calibrate = false
var printer: String?
var dpiArg: Double?
var reduce = 1
var lpOptions: [String] = []
var pageSizeArg: String?
var outPath: String?
var noRotate = false

var argv = Array(CommandLine.arguments.dropFirst())[...]
func value(_ name: String) -> String {
    guard let v = argv.popFirst() else { fail("\(name) needs a value\n\n\(usage)") }
    return v
}
while let a = argv.popFirst() {
    switch a {
    case "-h", "--help": print(usage); exit(0)
    case "calibrate" where input == nil && !calibrate: calibrate = true
    case "--printer": printer = value(a)
    case "--dpi":
        guard let v = Double(value(a)), v > 0 else { fail("--dpi must be a positive number") }
        dpiArg = v
    case "--reduce":
        guard let v = Int(value(a)), v >= 0 else { fail("--reduce must be a whole number, 0 or more") }
        reduce = v
    case "-o": lpOptions.append(value(a))
    case "--page-size": pageSizeArg = value(a)
    case "--out": outPath = value(a)
    case "--no-rotate": noRotate = true
    default:
        if a.hasPrefix("-") || input != nil { fail("unexpected argument: \(a)\n\n\(usage)") }
        input = a
    }
}
if !calibrate && input == nil { fail(usage) }

// MARK: - CUPS

@discardableResult
func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = pipe
    p.standardError = pipe
    guard (try? p.run()) != nil else { return (127, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

func defaultPrinter() -> String? {
    // "system default destination: NAME"
    let out = run("/usr/bin/lpstat", ["-d"]).output
    guard let r = out.range(of: "destination: ") else { return nil }
    return out[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
}

func driverDPI(_ queue: String) -> Double? {
    // "Resolution/Resolution: *203dpi 300dpi"
    let out = run("/usr/bin/lpoptions", ["-p", queue, "-l"]).output
    guard let line = out.split(separator: "\n").first(where: { $0.hasPrefix("Resolution/") }),
          let current = line.split(separator: " ").first(where: { $0.hasPrefix("*") }) else { return nil }
    return Double(current.dropFirst().prefix(while: { $0.isNumber }))
}

let queue = printer ?? defaultPrinter()
if outPath == nil && queue == nil { fail("no default printer; pass --printer QUEUE or --out FILE.pdf") }
let dpi = dpiArg ?? queue.flatMap(driverDPI) ?? 203
let dot = 72 / dpi  // one printer dot in points

func send(_ pdf: URL, pageSize: String) -> Never {
    guard let queue else { fail("no printer") }
    var args = ["-d", queue, "-o", "PageSize=\(pageSize)", "-o", "scaling=100"]
    for o in lpOptions { args += ["-o", o] }
    let r = run("/usr/bin/lp", args + [pdf.path])
    print(r.output.trimmingCharacters(in: .whitespacesAndNewlines))
    exit(r.status)
}

func outputURL() -> URL {
    outPath.map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("print-label-\(getpid()).pdf")
}

// MARK: - Calibration sheet

if calibrate {
    // 4x6 page: rows of 6-dot bars with 1...8 dot gaps, in both directions.
    var media = CGRect(x: 0, y: 0, width: 288, height: 432)
    let url = outputURL()
    let pdf = CGContext(url as CFURL, mediaBox: &media, nil)!
    pdf.beginPDFPage(nil)
    func text(_ s: String, _ x: Double, _ y: Double, _ size: Double) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]))
        pdf.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, pdf)
    }
    func snap(_ v: Double) -> Double { (v / dot).rounded() * dot }
    text("print-label calibration, \(Int(dpi)) dpi", 16, 414, 9)
    text("A: bars across the paper   B: bars along the feed", 16, 403, 7)
    text("Find the smallest N where the gaps stay white in both.", 16, 394, 7)
    pdf.setFillColor(gray: 0, alpha: 1)
    for n in 1...8 {
        let top = snap(380 - Double(n - 1) * 46)
        text("N=\(n)", 16, top - 20, 9)
        var y = top
        for _ in 0..<8 {  // A: bars stacked down the page
            pdf.fill(CGRect(x: snap(60), y: y - 6 * dot, width: snap(90), height: 6 * dot))
            y -= Double(6 + n) * dot
        }
        var x = snap(180)
        for _ in 0..<8 {  // B: bars side by side
            pdf.fill(CGRect(x: x, y: top - snap(38), width: 6 * dot, height: snap(38)))
            x += Double(6 + n) * dot
        }
    }
    pdf.endPDFPage()
    pdf.closePDF()
    if outPath != nil { print("wrote \(url.path)"); exit(0) }
    print("""
    Calibration sheet sent to \(queue!). Find the smallest N whose gaps stay white.
    Suggested --reduce: N minus 3 (N=4 -> 1, N=5 -> 2, N<=3 -> 0).
    If thin bars break up or vanish, lower it; if gaps still fill in, raise it.
    """)
    send(url, pageSize: "Custom.288x432")
}

// MARK: - Label

guard let doc = CGPDFDocument(URL(fileURLWithPath: input!) as CFURL), doc.numberOfPages > 0 else {
    fail("can't open \(input!)")
}

let twoD: Set<VNBarcodeSymbology> = [.qr, .microQR, .aztec, .dataMatrix, .pdf417, .microPDF417]

func render(_ page: CGPDFPage, scale: Double, antialias: Bool) -> CGContext {
    let box = page.getBoxRect(.mediaBox)
    let w = Int((box.width * scale).rounded()), h = Int((box.height * scale).rounded())
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setShouldAntialias(antialias)
    ctx.interpolationQuality = antialias ? .high : .none
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: -box.minX, y: -box.minY)
    ctx.drawPDFPage(page)
    return ctx
}

func barcodes(_ img: CGImage) -> [VNBarcodeObservation] {
    let r = VNDetectBarcodesRequest()
    try? VNImageRequestHandler(cgImage: img).perform([r])
    return r.results ?? []
}

func payloads(_ obs: [VNBarcodeObservation]) -> [String] {
    obs.compactMap { o in o.payloadStringValue.map { "\(o.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")): \($0)" } }.sorted()
}

let url = outputURL()
var media = CGRect.zero
let out = CGContext(url as CFURL, mediaBox: nil, nil)!
var firstPageSize = ""

for n in 1...doc.numberOfPages {
    let page = doc.page(at: n)!
    if page.rotationAngle % 360 != 0 { fail("page \(n) has /Rotate \(page.rotationAngle); rotated pages aren't supported yet") }
    let box = page.getBoxRect(.mediaBox)

    // 1. Find barcodes in a high-resolution render of the original.
    let found = barcodes(render(page, scale: 600 / 72, antialias: true).makeImage()!)
    let expected = payloads(found)
    let linear = found.filter { !twoD.contains($0.symbology) }
    for p in expected { print("page \(n) original   \(p)") }
    if linear.isEmpty { print("page \(n): no 1D barcode found; printing without bar thinning") }

    // 2. Render at printer resolution, 1-bit.
    let ctx = render(page, scale: dpi / 72, antialias: false)
    let W = ctx.width, H = ctx.height
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: W * H)
    for i in 0..<(W * H) { px[i] = px[i] < 128 ? 0 : 255 }

    // Runs of black dots along a barcode's stacking axis, inside its box.
    struct Region { let x: Range<Int>, y: Range<Int>, stackedAlongY: Bool }
    func eachRun(_ r: Region, _ buf: UnsafeMutablePointer<UInt8>, _ body: (_ start: Int, _ end: Int, _ index: (Int) -> Int) -> Void) {
        let (outer, inner) = r.stackedAlongY ? (r.x, r.y) : (r.y, r.x)
        for o in outer {
            let at: (Int) -> Int = { i in r.stackedAlongY ? i * W + o : o * W + i }
            var i = inner.lowerBound
            while i < inner.upperBound {
                guard buf[at(i)] == 0 else { i += 1; continue }
                var e = i
                while e < inner.upperBound && buf[at(e)] == 0 { e += 1 }
                body(i, e, at)
                i = e
            }
        }
    }

    // 3. Thin the bars of each 1D barcode (bitmap rows run top-down).
    var regions: [Region] = []
    for b in linear {
        let bb = b.boundingBox
        let x0 = max(0, Int(bb.minX * Double(W)) - 2), x1 = min(W, Int(bb.maxX * Double(W)) + 2)
        let y0 = max(0, Int((1 - bb.maxY) * Double(H)) - 2), y1 = min(H, Int((1 - bb.minY) * Double(H)) + 2)
        // Bars are stacked along whichever axis has more black/white changes.
        var alongX = 0, alongY = 0
        for y in stride(from: y0, to: y1, by: max(1, (y1 - y0) / 16)) {
            for x in (x0 + 1)..<x1 where px[y * W + x] != px[y * W + x - 1] { alongX += 1 }
        }
        for x in stride(from: x0, to: x1, by: max(1, (x1 - x0) / 16)) {
            for y in (y0 + 1)..<y1 where px[y * W + x] != px[(y - 1) * W + x] { alongY += 1 }
        }
        let stackedAlongY = alongY > alongX
        let region = Region(x: x0..<x1, y: y0..<y1, stackedAlongY: stackedAlongY)
        regions.append(region)
        guard reduce > 0 else { continue }
        eachRun(region, px) { start, end, at in
            for k in max(start + 1, end - reduce)..<end { px[at(k)] = 255 }  // keep at least 1 dot
        }
        print("page \(n): thinned \(b.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")) bars by \(reduce) dot(s), stacked along \(stackedAlongY ? "y" : "x")")
    }
    let bitmap = ctx.makeImage()!

    // 4. Every barcode must still decode to the same value. Decoders misread the deliberately thin
    // bars of the raw bitmap, so check a simulated print instead: each bar spread back by `reduce`
    // dots, as the print head does. This catches lost or merged bars and wrong regions.
    let sim = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    sim.draw(bitmap, in: CGRect(x: 0, y: 0, width: W, height: H))
    let spx = sim.data!.bindMemory(to: UInt8.self, capacity: W * H)
    for r in regions where reduce > 0 {
        let limit = r.stackedAlongY ? r.y.upperBound : r.x.upperBound
        eachRun(r, px) { _, end, at in  // scan the thinned bitmap, write the copy
            for k in end..<min(end + reduce, limit) { spx[at(k)] = 0 }
        }
    }
    let up = CGContext(data: nil, width: W * 4, height: H * 4, bitsPerComponent: 8, bytesPerRow: W * 4,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    up.interpolationQuality = .none
    up.draw(sim.makeImage()!, in: CGRect(x: 0, y: 0, width: W * 4, height: H * 4))
    let got = payloads(barcodes(up.makeImage()!))
    let missing = expected.filter { !got.contains($0) }
    if !missing.isEmpty {
        fail("page \(n): after processing these no longer decode, not printing:\n  " + missing.joined(separator: "\n  "))
    }
    print("page \(n): \(expected.count) barcode(s) verified at \(Int(dpi)) dpi, \(W)x\(H) dots")

    // 5. Add the page to the output PDF at its original size. The paper feeds from the top of the
    // page, so bars stacked down the page lie across the print head. Dense rows of bars across the
    // head build up heat and fill in the gaps, so turn the page 90 degrees to run them along the feed.
    let size = box.size
    let rotate = !noRotate && regions.contains { $0.stackedAlongY }
    media = CGRect(x: 0, y: 0, width: rotate ? size.height : size.width, height: rotate ? size.width : size.height)
    if n == 1 { firstPageSize = "Custom.\(Int(media.width))x\(Int(media.height))" }
    if rotate { print("page \(n): rotated 90 degrees so barcode bars run along the paper feed") }
    out.beginPage(mediaBox: &media)
    out.interpolationQuality = .none
    if rotate {
        out.translateBy(x: size.height, y: 0)
        out.rotate(by: .pi / 2)
    }
    out.draw(bitmap, in: CGRect(origin: .zero, size: size))
    out.endPage()
}
out.closePDF()

if outPath != nil { print("wrote \(url.path)"); exit(0) }
send(url, pageSize: pageSizeArg ?? firstPageSize)
