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
