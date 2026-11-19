import AppKit
import PDFKit
// usage: swift make-fixtures.swift <outDir>   (synthetic files only, no personal data)
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ lines: [(String, CGFloat, Bool)], size: NSSize, bg: NSColor) -> NSImage {
    NSImage(size: size, flipped: true) { r in
        bg.setFill(); r.fill()
        var y: CGFloat = 40
        for (t, sz, bold) in lines {
            let font = NSFont.systemFont(ofSize: sz, weight: bold ? .bold : .regular)
            (t as NSString).draw(at: NSPoint(x: 48, y: y), withAttributes: [.font: font, .foregroundColor: NSColor.black])
            y += sz * 1.6
        }
        return true
    }
}
func png(_ img: NSImage, _ name: String) {
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

// Screenshot of a fake spreadsheet.
png(draw([("Quarterly Budget Forecast 2027", 34, true), ("Department      Q1        Q2        Q3        Q4", 22, false),
          ("Marketing        42,000    45,500    39,000    51,200", 22, false),
          ("Engineering     118,400   121,900   125,000   130,300", 22, false),
          ("Operations       36,750    37,100    38,900    40,000", 22, false),
          ("Total           197,150   204,500   202,900   221,500", 22, true)],
         size: NSSize(width: 1100, height: 420), bg: .white), "Screenshot 2026-11-19 at 10.15.00.png")

// PDF with a real text layer: an invoice.
let invoice = [("ACME Plumbing Ltd", 22, true), ("INVOICE", 30, true), ("Invoice number INV-20481", 16, false),
               ("Invoice date 2 November 2026", 16, false), ("Bill to Harbour Street Dental Practice", 16, false),
               ("Emergency pipe repair and boiler service", 16, false), ("Labour 6 hours 540.00", 16, false),
               ("Parts and materials 744.50", 16, false), ("Amount due 1,284.50 payable within 30 days", 16, true)]
let page = NSImage(size: NSSize(width: 612, height: 792), flipped: true) { r in
    NSColor.white.setFill(); r.fill()
    var y: CGFloat = 60
    for (t, sz, bold) in invoice {
        (t as NSString).draw(at: NSPoint(x: 56, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: CGFloat(sz), weight: bold ? .bold : .regular), .foregroundColor: NSColor.black])
        y += CGFloat(sz) * 1.9
    }
    return true
}
// Vector PDF so the text layer exists.
var box = CGRect(x: 0, y: 0, width: 612, height: 792)
let ctx = CGContext(out.appendingPathComponent("invoice-text.pdf") as CFURL, mediaBox: &box,
                    [kCGPDFContextTitle: "Untitled", kCGPDFContextAuthor: "ACME Plumbing Ltd"] as CFDictionary)!
ctx.beginPDFPage(nil)
let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
ctx.translateBy(x: 0, y: 792); ctx.scaleBy(x: 1, y: -1)
var y: CGFloat = 60
for (t, sz, bold) in invoice {
    (t as NSString).draw(at: NSPoint(x: 56, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: CGFloat(sz), weight: bold ? .bold : .regular), .foregroundColor: NSColor.black])
    y += CGFloat(sz) * 1.9
}
NSGraphicsContext.restoreGraphicsState()
ctx.endPDFPage(); ctx.closePDF()

// Scanned-style PDF: the same page as an image only (no text layer) to exercise OCR.
let doc = PDFDocument(); doc.insert(PDFPage(image: page)!, at: 0)
doc.write(to: out.appendingPathComponent("invoice-scanned.pdf"))
print("fixtures written to \(out.path)")
