import AppKit
// usage: swift make-eval-cases.swift <outDir>
// Synthetic screenshots (no personal data) for judging naming quality: `relabel eval Evals/cases.json`.
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let ink = NSColor(white: 0.1, alpha: 1), grey = NSColor(white: 0.45, alpha: 1)

struct Canvas {
    let size: NSSize
    var ops: [(NSRect) -> Void] = []
    mutating func fill(_ r: NSRect, _ c: NSColor, radius: CGFloat = 0) {
        ops.append { _ in c.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() }
    }
    mutating func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 18, bold: Bool = false,
                       color: NSColor = ink, mono: Bool = false, right: CGFloat? = nil) {
        ops.append { _ in
            let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
                            : NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let w = (s as NSString).size(withAttributes: attrs).width
            (s as NSString).draw(at: NSPoint(x: right.map { $0 - w } ?? x, y: y), withAttributes: attrs)
        }
    }
    func save(_ name: String, bg: NSColor = .white) {
        let img = NSImage(size: size, flipped: true) { r in
            bg.setFill(); r.fill()
            for op in ops { op(r) }
            return true
        }
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}

// 1. Flight results: three cards laid out in columns.
do {
    var c = Canvas(size: NSSize(width: 1200, height: 700))
    let rows = [("16:20", "4h", "20:20", "1 stop BLR", "₹9,845", "12 deals from"), ("07:05", "5h 10", "12:15", "1 stop HYD", "₹8,990", "9 deals from"),
                ("19:40", "3h 55", "23:35", "Direct", "₹11,320", "6 deals from")]
    for (i, r) in rows.enumerated() {
        let y = CGFloat(20 + i * 225)
        c.fill(NSRect(x: 20, y: y, width: 1160, height: 205), .white, radius: 14)
        c.text("Air Meridian", 50, y + 16, 15, bold: true)
        c.text(r.0, 220, y + 60, 38); c.text("PNQ", 240, y + 112, 22, color: grey)
        c.text(r.1, 440, y + 52, 17, color: grey); c.text(r.3, 420, y + 118, 17, color: .systemPink)
        c.text(r.2, 590, y + 60, 38); c.text("BOM", 610, y + 112, 22, color: grey)
        c.text(r.5, 840, y + 40, 16, color: grey); c.text(r.4, 840, y + 70, 36, bold: true)
        c.fill(NSRect(x: 840, y: y + 130, width: 320, height: 54), NSColor(red: 0.1, green: 0.14, blue: 0.25, alpha: 1), radius: 10)
        c.text("Select  →", 940, y + 143, 24, bold: true, color: .white)
    }
    c.save("flights-pune-mumbai.png", bg: NSColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1))
}

// 2. Chat conversation.
do {
    var c = Canvas(size: NSSize(width: 760, height: 620))
    c.fill(NSRect(x: 0, y: 0, width: 760, height: 70), NSColor(white: 0.95, alpha: 1))
    c.text("Priya Nair", 30, 14, 22, bold: true); c.text("online", 30, 42, 14, color: grey)
    let msgs: [(String, Bool)] = [("Are we still on for dinner on Friday?", false), ("Yes! 8 pm works for me", true),
                                  ("I booked a table at Olive Bistro, it is near the station", false), ("Perfect, I will bring the wine", true),
                                  ("Can you also send me the address?", false)]
    var y: CGFloat = 100
    for (m, mine) in msgs {
        let w = CGFloat(m.count) * 10.5 + 40
        let x: CGFloat = mine ? 730 - w : 30
        c.fill(NSRect(x: x, y: y, width: w, height: 50), mine ? NSColor(red: 0.85, green: 0.96, blue: 0.8, alpha: 1) : NSColor(white: 0.94, alpha: 1), radius: 14)
        c.text(m, x + 18, y + 13, 18)
        y += 70
    }
    c.save("chat-dinner-plans.png")
}

// 3. Build error.
do {
    var c = Canvas(size: NSSize(width: 980, height: 360))
    c.fill(NSRect(x: 0, y: 0, width: 980, height: 40), NSColor(white: 0.9, alpha: 1))
    c.text("LoginView.swift", 20, 10, 15, bold: true)
    c.fill(NSRect(x: 0, y: 150, width: 980, height: 48), NSColor(red: 1, green: 0.88, blue: 0.88, alpha: 1))
    c.text("41    let user = try await session.fetchUser(id: userID)", 24, 60, 16, mono: true)
    c.text("42    let name = fetchUserName(user)", 24, 90, 16, mono: true)
    c.text("43    showWelcome(name)", 24, 120, 16, mono: true)
    c.text("Cannot find 'fetchUserName' in scope", 24, 162, 20, bold: true, color: .systemRed)
    c.text("Build Failed – 1 error", 24, 230, 18, bold: true); c.text("Xcode  •  Build target Relabel  •  Debug", 24, 262, 15, color: grey)
    c.save("xcode-build-error.png")
}

// 4. Invoice.
do {
    var c = Canvas(size: NSSize(width: 800, height: 760))
    c.text("Northwind Cleaning Services", 50, 40, 26, bold: true); c.text("INVOICE", 560, 44, 30, bold: true, color: grey)
    c.text("Invoice number: 4471", 50, 110, 18); c.text("Date: 14 October 2026", 50, 140, 18)
    c.text("Billed to: Greenfield Dental Clinic", 50, 190, 18)
    c.text("Office deep clean, 3 floors", 50, 270, 18); c.text("$240.00", 0, 270, 18, right: 750)
    c.text("Window cleaning", 50, 310, 18); c.text("$80.00", 0, 310, 18, right: 750)
    c.text("Total due: $320.00", 480, 400, 22, bold: true)
    c.text("Payment due within 14 days", 50, 470, 16, color: grey)
    c.save("invoice-northwind.png")
}

// 5. Code / traceback in a terminal.
do {
    var c = Canvas(size: NSSize(width: 900, height: 340))
    let lines = ["$ python import_orders.py", "Traceback (most recent call last):", "  File \"import_orders.py\", line 27, in <module>",
                 "    total = sum(row[\"amount\"] for row in rows)", "KeyError: 'amount'", "$ "]
    for (i, l) in lines.enumerated() { c.text(l, 24, CGFloat(24 + i * 30), 18, color: i == 4 ? .systemRed : .white, mono: true) }
    c.save("terminal-keyerror.png", bg: NSColor(white: 0.1, alpha: 1))
}

// 6. Email.
do {
    var c = Canvas(size: NSSize(width: 900, height: 520))
    c.text("Q3 roadmap review moved to Thursday", 40, 30, 26, bold: true)
    c.text("Daniel Ortiz", 40, 90, 18, bold: true); c.text("to me, Mei Lin", 40, 118, 15, color: grey); c.text("Tue, 3 Nov, 9:14 AM", 0, 92, 15, color: grey, right: 860)
    c.text("Hi all,", 40, 190, 18)
    c.text("The roadmap review has moved from Wednesday to Thursday at 3 pm", 40, 230, 18)
    c.text("because of the customer visit. Please send your slides by Wednesday night.", 40, 260, 18)
    c.text("Thanks, Daniel", 40, 320, 18)
    c.save("email-roadmap-review.png")
}

// 7. Settings pane.
do {
    var c = Canvas(size: NSSize(width: 820, height: 520))
    c.text("Battery", 40, 30, 30, bold: true)
    c.text("Low Power Mode", 40, 110, 20); c.text("Only on battery", 0, 110, 18, color: grey, right: 760)
    c.text("Battery Health", 40, 170, 20); c.text("Normal  •  Maximum capacity 92%", 0, 170, 18, color: grey, right: 760)
    c.text("Optimized Battery Charging", 40, 230, 20); c.text("On", 0, 230, 18, color: grey, right: 760)
    c.text("Show battery percentage in menu bar", 40, 290, 20); c.text("On", 0, 290, 18, color: grey, right: 760)
    c.text("System Settings", 40, 450, 14, color: grey)
    c.save("settings-battery.png", bg: NSColor(white: 0.96, alpha: 1))
}

// 8. Analytics dashboard.
do {
    var c = Canvas(size: NSSize(width: 1100, height: 520))
    c.text("Weekly overview", 40, 30, 28, bold: true); c.text("Nov 9 – Nov 15", 0, 38, 16, color: grey, right: 1060)
    let tiles = [("Active users", "12,480", "+8.2%"), ("New signups", "1,126", "+3.1%"), ("Churn rate", "2.4%", "-0.3%")]
    for (i, t) in tiles.enumerated() {
        let x = CGFloat(40 + i * 350)
        c.fill(NSRect(x: x, y: 110, width: 320, height: 170), NSColor(white: 0.96, alpha: 1), radius: 12)
        c.text(t.0, x + 24, 130, 17, color: grey); c.text(t.1, x + 24, 170, 44, bold: true); c.text(t.2, x + 24, 235, 18, color: .systemGreen)
    }
    c.text("Acme Analytics  •  Dashboard", 40, 450, 15, color: grey)
    c.save("dashboard-weekly-users.png")
}

// 9. Product page.
do {
    var c = Canvas(size: NSSize(width: 1000, height: 560))
    c.fill(NSRect(x: 40, y: 40, width: 380, height: 380), NSColor(white: 0.9, alpha: 1), radius: 20)
    c.text("Aurora Noise Cancelling Headphones", 460, 50, 28, bold: true)
    c.text("★★★★☆  4.5  (2,318 ratings)", 460, 130, 18, color: grey)
    c.text("$249.00", 460, 180, 40, bold: true)
    c.text("Free delivery by Friday, 20 Nov", 460, 250, 17); c.text("40 hour battery life, Bluetooth 5.3", 460, 285, 17)
    c.fill(NSRect(x: 460, y: 350, width: 300, height: 56), .systemOrange, radius: 12); c.text("Add to cart", 530, 365, 22, bold: true, color: .white)
    c.save("product-headphones.png")
}

// 10. Recipe.
do {
    var c = Canvas(size: NSSize(width: 900, height: 560))
    c.text("Creamy Tomato Pasta", 40, 30, 34, bold: true); c.text("Prep 10 min  •  Cook 20 min  •  Serves 4", 40, 82, 17, color: grey)
    c.text("Ingredients", 40, 150, 22, bold: true)
    for (i, l) in ["400 g penne", "2 cups crushed tomatoes", "1/2 cup cream", "3 cloves garlic", "Fresh basil"].enumerated() { c.text("•  " + l, 40, CGFloat(190 + i * 34), 18) }
    c.text("Method", 460, 150, 22, bold: true)
    c.text("1. Boil the pasta until al dente.", 460, 190, 18); c.text("2. Fry garlic, add tomatoes and simmer.", 460, 224, 18); c.text("3. Stir in cream and basil.", 460, 258, 18)
    c.save("recipe-tomato-pasta.png")
}
print("wrote eval images to \(out.path)")
