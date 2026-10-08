// Builds a synthetic 4x6 label: two Code 128 barcodes (one per bar direction) with the same
// narrow-module size as an Australia Post MyPost label (0.84pt), a QR code and some text.
// All data is made up. Usage: swift Tests/make-fixture.swift out.pdf
import Foundation
import CoreGraphics
import CoreImage
import CoreText

let module = 1.28 * 0.6572  // pt, MyPost Code 128 narrow module
let ci = CIContext()
func code(_ filter: String, _ message: String) -> CGImage {
    let f = CIFilter(name: filter)!
    f.setValue(message.data(using: .ascii), forKey: "inputMessage")
    if filter == "CICode128BarcodeGenerator" { f.setValue(0, forKey: "inputQuietSpace") }
    let img = f.outputImage!
    return ci.createCGImage(img, from: img.extent)!
}

var media = CGRect(x: 0, y: 0, width: 286, height: 430)
let pdf = CGContext(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, mediaBox: &media, nil)!
pdf.beginPDFPage(nil)
pdf.interpolationQuality = .none

// Bars stacked down the page (like MyPost): rotate the barcode 90 degrees.
let a = code("CICode128BarcodeGenerator", "0100000000000000910000000012345678")
pdf.saveGState()
pdf.translateBy(x: 270, y: 60)
pdf.rotate(by: .pi / 2)
pdf.draw(a, in: CGRect(x: 0, y: 0, width: Double(a.width) * module, height: 50))
pdf.restoreGState()

// Bars side by side.
let b = code("CICode128BarcodeGenerator", "TEST-LABEL-0000123456789")
pdf.draw(b, in: CGRect(x: 16, y: 40, width: Double(b.width) * module, height: 40))

let q = code("CIQRCodeGenerator", "https://example.com/not-a-real-label")
pdf.draw(q, in: CGRect(x: 16, y: 300, width: 80, height: 80))

let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
let line = CTLineCreateWithAttributedString(NSAttributedString(
    string: "SYNTHETIC TEST LABEL - NOT FOR POSTAGE", attributes: [kCTFontAttributeName as NSAttributedString.Key: font]))
pdf.textPosition = CGPoint(x: 16, y: 400)
CTLineDraw(line, pdf)
pdf.endPDFPage()
pdf.closePDF()
