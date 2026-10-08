// Prints every barcode found in page 1 of a PDF rendered at 600 dpi, sorted, one per line.
import Foundation
import CoreGraphics
import Vision
let page = CGPDFDocument(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL)!.page(at: 1)!
let box = page.getBoxRect(.mediaBox), s = 600.0 / 72
let ctx = CGContext(data: nil, width: Int(box.width * s), height: Int(box.height * s), bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
ctx.setFillColor(gray: 1, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
ctx.interpolationQuality = .none
ctx.scaleBy(x: s, y: s)
ctx.drawPDFPage(page)
let r = VNDetectBarcodesRequest()
try! VNImageRequestHandler(cgImage: ctx.makeImage()!).perform([r])
for p in (r.results ?? []).compactMap({ $0.payloadStringValue }).sorted() { print(p) }
