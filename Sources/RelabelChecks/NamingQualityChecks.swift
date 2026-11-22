import Foundation
import RelabelCore

enum NamingQualityChecks {
    static func rows() {
        func box(_ t: String, _ x: Double, _ y: Double) -> TextBox { TextBox(text: t, minX: x, maxX: x + 0.1, minY: y, maxY: y + 0.04) }
        // A flight card: times and codes sit on rows, with a repeated Select button.
        let boxes = [box("07:40", 0.1, 0.80), box("11:40", 0.6, 0.801), box("IDR", 0.1, 0.70), box("COK", 0.6, 0.699),
                     box("Select", 0.8, 0.5), box("Select", 0.8, 0.3), box("Select", 0.8, 0.1), box("SkyLark", 0.1, 0.9)]
        let lines = OCRRows.lines(boxes)
        check(lines == ["SkyLark", "07:40 | 11:40", "IDR | COK", "Select"], "rows grouped, repeated Select kept once: \(lines)")
        check(OCRRows.lines([box("Hello", 0.1, 0.9), box("World", 0.1, 0.8)]) == ["Hello", "World"], "separate lines stay separate")
    }

    static func titles() {
        check(TitleCheck.problem("SkyLark flights IDR to COK", length: .standard) == nil, "good title passes")
        check(TitleCheck.problem("Flights", length: .standard) != nil, "one word is generic")
        check(TitleCheck.problem("Click the select button", length: .standard) != nil, "UI words rejected")
        check(TitleCheck.problem("One two three four five six seven eight nine ten eleven", length: .standard) != nil, "too long rejected")
        check(TitleCheck.stripped("SkyLark deals flights Select") == "SkyLark flights", "UI words stripped")
        check(TitleCheck.trimmed("a b c d e f g h i j k l m", length: .short).split(separator: " ").count == 8, "trimmed to the cap")
        check(TitleCheck.trimmed("Attention Is Not Enough Sparse Routing for Long Context", length: .short) == "Attention Is Not Enough Sparse Routing", "trim cuts at a natural break")
        check(Sanitizer.restoreProperNames("Northwind traders invoice #4471", source: "NORTHWIND TRADERS\nINVOICE #4471") == "Northwind Traders invoice #4471", "all-caps company name restored")
        check(Sanitizer.calmCaps("ACME AUTOMATION SYSTEMS PVT.LTD quotation") == "Acme Automation Systems quotation", "caps company calmed")
        check(Sanitizer.calmCaps("Travel Visa application LARSEN") == "Travel Visa application Larsen", "caps surname calmed")
        check(Sanitizer.calmCaps("CNC retrofit for HVAC") == "CNC retrofit for HVAC", "short acronyms kept")
        check(Sanitizer.restoreIdentifiers("Delivery Challan d0457", source: "Delivery Challan# D0457") == "Delivery Challan D0457", "identifier case restored")
        check(RuleNamer.name(for: "NOVA CONTROL SYSTEMS PVT. LTD\nNo.40/A\nQuotation Nr.: 5520193\nCustomer: ACME AUTOMATION SYSTEMS PVT.LTD", length: .standard)?.title == "Nova Control Systems quotation 5520193", "quotation Nr: \(RuleNamer.name(for: "NOVA CONTROL SYSTEMS PVT. LTD\nQuotation Nr.: 5520193", length: .standard)?.title ?? "nil")")
        check(RuleNamer.name(for: "CITY WATER BOARD\nTender for supply of PIPE FITTINGS\nTender No.: CWB/STORES-U2 PURCHASE/TW202400731905 dated 14-03-\n2024", length: .standard)?.title == "Tender TW202400731905", "tender id")
        check(RuleNamer.name(for: "ACME | AUTOMATION\nDelivery Challan\nAcme Automation Systems Pvt. Ltd.\nDelivery Challan# D0457", length: .standard)?.title == "Acme Automation Systems delivery challan D0457", "delivery challan")
        check(Sanitizer.restoreProperNames("Flights to kochi", source: "Indore to Kochi\\nFlights to Kochi today") == "Flights to Kochi", "place name capital restored")
    }

    static func listing() {
        let skylark = "SkyLark\n16 deals from\n07:40 | 4h | 11:40 | ₴8,615\nIDR | 1 stop BLR | COK\nSelect →\n17 deals from\n09:15 | 8h 40 | 18:05 | ₴8,240\nIDR | 1 stop HYD | COK\n"
        let f = ListingFacts.extract(from: skylark)
        check(f?.from == "IDR" && f?.to == "COK", "route found: \(String(describing: f))")
        check(f?.cheapest == "₹8,240", "cheapest price with rupee sign: \(f?.cheapest ?? "nil")")
        check(f?.carrier == "SkyLark", "carrier: \(f?.carrier ?? "nil")")
        check(f?.title(length: .standard) == "SkyLark flights IDR to COK from ₹8,240", "built title: \(f?.title(length: .standard) ?? "nil")")
        check(f?.isReflected(in: "SkyLark schedule") == false && f?.isReflected(in: "SkyLark flights IDR to COK") == true, "route reflected check")
        let header = "Indore (IDR) - Kochi (COK) • 1 adult\n7 results\n07:40 | 11:40 | ₹8,615\nIDR | COK\n"
        let h = ListingFacts.extract(from: header)
        check(h?.fromCity == "Indore" && h?.toCity == "Kochi", "cities from header: \(String(describing: h))")
        check(ListingFacts.extract(from: "Quarterly budget\nDepartment | Q1 | Q2\nTotal | 197,150") == nil, "ordinary text gives no facts")
        check(ListingFacts.extract(from: "CNC | PLC\nretrofit of machines") == nil, "two codes without times are not a route")
    }

    static func shopping() {
        let hotels = "Hotels in Goa\n3 properties found\nSeaview Resort & Spa\n★★★★ 9.1 Excellent (812 reviews) | ₹4,200\nper night\nPalm Grove Inn\n₹3,150 | per night\nCoral Bay Hotel\n₹5,600\nper night"
        check(RuleNamer.name(for: hotels, length: .standard)?.title == "Hotels in Goa from ₹3,150 per night", "hotel list: \(RuleNamer.name(for: hotels, length: .standard)?.title ?? "nil")")
        check(RuleNamer.name(for: hotels, length: .short)?.title == "Hotels in Goa", "short hotel list")
        let one = "Seaview Resort & Spa\n★★★★ 9.1 (812 reviews)\n₹4,200\nper night\nBook now"
        check(RuleNamer.name(for: one, length: .standard)?.title == "Seaview Resort & Spa ₹4,200 per night", "single hotel: \(RuleNamer.name(for: one, length: .standard)?.title ?? "nil")")
        let product = "Trailhead 40L Hiking Backpack\n★★★★☆ 4.6 (5,402 ratings)\n$89.99\nIn stock. Free shipping over $50\nBuy now"
        check(RuleNamer.name(for: product, length: .standard)?.title == "Trailhead 40L Hiking Backpack $89.99", "product: \(RuleNamer.name(for: product, length: .standard)?.title ?? "nil")")
        check(RuleNamer.name(for: product, length: .short)?.title == "Trailhead 40L Hiking Backpack", "product short")
        check(RuleNamer.name(for: "Meeting notes\nBuy now pay later is great\nNo price here", length: .standard) == nil, "no price, no rule name")
        check(RuleNamer.name(for: "Quarterly budget\nTotal | $197,150 per night shift", length: .standard) == nil, "budget text is left to the model")
    }
}

extension NamingQualityChecks {
    static func documents() {
        let plate1 = "Kestrel Controls KESTREL\nAB (Sweden)\nMODEL:DRIVE UNIT+FAN KIT-B\nSN:\n(SN) 880044556677112\nVERSION:\nPWR DIAL SET\n01A 01A 00A\nK14\nR09"
        check(RuleNamer.name(for: plate1, length: .standard)?.title == "Kestrel DRIVE UNIT+FAN KIT-B SN 880044556677112", "nameplate 1: \(RuleNamer.name(for: plate1, length: .standard)?.title ?? "nil")")
        let plate2 = "KESTREL\nVERS:\nPWR SET\n00A 00A\nSN: 880044556677113\nM: COMPACT KEYPAD"
        check(RuleNamer.name(for: plate2, length: .standard)?.title == "Kestrel COMPACT KEYPAD SN 880044556677113", "nameplate 2: \(RuleNamer.name(for: plate2, length: .standard)?.title ?? "nil")")
        let plate3 = "elrsK\nSN: 8800445 51200037\nM: DRIVE UNIT+FAN KIT\n00A 00A 02A\nPWR DIAL SET\nVERS:"
        check(RuleNamer.name(for: plate3, length: .standard)?.title == "DRIVE UNIT+FAN KIT SN 8800445 51200037", "nameplate 3 (garbled brand dropped): \(RuleNamer.name(for: plate3, length: .standard)?.title ?? "nil")")
        check(RuleNamer.name(for: "Meeting about SN numbers\nno label here", length: .standard) == nil, "no serial, no nameplate")

        let invoice = "ACME Plumbing Ltd\nINVOICE\nInvoice number INV-20481\nInvoice date 2 November 2026\nAmount due 1,284.50"
        check(RuleNamer.name(for: invoice, length: .standard)?.title == "ACME Plumbing invoice INV-20481", "invoice: \(RuleNamer.name(for: invoice, length: .standard)?.title ?? "nil")")
        check(RuleNamer.name(for: "Invoice\nInvoice Date 2 November\nthanks", length: .standard) == nil, "no number, no company: left to the model")

        let orbit = "ORBIT AUTOMATION\nPAYMENT TERMS\nSCOPE OF SUPPLY\nINR 75,000.00"
        check(RuleNamer.name(for: orbit, length: .standard)?.title == "Orbit Automation payment terms", "caps company + heading: \(RuleNamer.name(for: orbit, length: .standard)?.title ?? "nil")")
        let heavy = "INSPECTION AND REPAIRS\nPump Inspection\nRiverbend Water Works Limited, ELMSTEAD -560 210\nScope of the visit"
        check(RuleNamer.name(for: heavy, length: .standard)?.title == "Riverbend Water Works inspection and repairs", "Limited company + heading: \(RuleNamer.name(for: heavy, length: .standard)?.title ?? "nil")")
        let cropped = "SPECTION AND REPAIRS\nPump Inspection\nr Works Limited, ELMSTEAD -560 210"
        check(RuleNamer.name(for: cropped, length: .standard) == nil, "cropped heading is not trusted")
    }
}

extension NamingQualityChecks {
    static func errors() {
        func t(_ s: String, _ l: NameLength = .standard) -> String { RuleNamer.name(for: s, length: l)?.title ?? "nil" }
        let py = "$ python import_orders.py\nTraceback (most recent call last):\nFile \"import_orders.py\", line 27, in <module>\ntotal = sum(row[\"amount\"] for row in rows)\nKeyError: 'amount'\n$"
        check(t(py) == "Python KeyError amount in import_orders", "python: \(t(py))")
        check(t(py, .short) == "Python KeyError amount", "python short: \(t(py, .short))")
        let x = "LoginView.swift\nlet name = fetchUserName(user)\nCannot find 'fetchUserName' in scope\nBuild Failed - 1 error\nXcode"
        check(t(x) == "Xcode error cannot find fetchUserName in scope", "xcode: \(t(x))")
        check(t("Uncaught TypeError: Cannot read properties of undefined (reading 'map')\n    at render (app.js:10)") == "JavaScript TypeError Cannot read properties of undefined (reading map)", "js: \(t("Uncaught TypeError: Cannot read properties of undefined (reading 'map')"))")
        check(t("error[E0382]: borrow of moved value: `v`\n --> src/main.rs") == "Rust error E0382 borrow of moved value: v", "rust: \(t("error[E0382]: borrow of moved value: `v`"))")
        check(t("jash@mac ~ % pnpm install\nzsh: command not found: pnpm") == "Terminal error command not found pnpm", "shell")
        check(RuleNamer.name(for: "Notes about KeyError handling\nwe should add tests", length: .standard) == nil, "talking about an error is not an error screen")
    }

    static func chats() {
        check(ChatFacts.contact(in: "Priya Nair\nonline\nAre we still on for dinner?") == "Priya Nair", "contact above online")
        check(ChatFacts.contact(in: "Mom\nlast seen today at 9:41 AM\nhello") == "Mom", "last seen")
        check(ChatFacts.contact(in: "Quarterly Budget\nonline\nDepartment") == nil || ChatFacts.contact(in: "Quarterly Budget\nonline\nDepartment") == "Quarterly Budget", "title-case line above 'online' only")
        check(ChatFacts.contact(in: "Weekly overview\nNov 9 - Nov 15\nActive users") == nil, "dashboard is not a chat")
        check(ChatFacts.finalTitle("Dinner plans", contact: "Priya Nair") == "Chat with Priya Nair", "contact added when model leaves it out")
        check(ChatFacts.finalTitle("Chat with priya Nair about dinner", contact: "Priya Nair") == "Chat with Priya Nair about dinner", "contact capitals restored")
        check(ChatFacts.finalTitle("Chat with Priya about dinner on Friday", contact: "Priya Nair") == "Chat with Priya about dinner on Friday", "model title kept when it has the contact")
    }
}
