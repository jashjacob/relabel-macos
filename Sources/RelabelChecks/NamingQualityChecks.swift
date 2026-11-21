import Foundation
import RelabelCore

enum NamingQualityChecks {
    static func rows() {
        func box(_ t: String, _ x: Double, _ y: Double) -> TextBox { TextBox(text: t, minX: x, maxX: x + 0.1, minY: y, maxY: y + 0.04) }
        // A flight card: times and codes sit on rows, with a repeated Select button.
        let boxes = [box("16:20", 0.1, 0.80), box("20:20", 0.6, 0.801), box("ISK", 0.1, 0.70), box("MAA", 0.6, 0.699),
                     box("Select", 0.8, 0.5), box("Select", 0.8, 0.3), box("Select", 0.8, 0.1), box("IndiGo", 0.1, 0.9)]
        let lines = OCRRows.lines(boxes)
        check(lines == ["IndiGo", "16:20 | 20:20", "ISK | MAA", "Select"], "rows grouped, repeated Select kept once: \(lines)")
        check(OCRRows.lines([box("Hello", 0.1, 0.9), box("World", 0.1, 0.8)]) == ["Hello", "World"], "separate lines stay separate")
    }

    static func titles() {
        check(TitleCheck.problem("IndiGo flights ISK to MAA", length: .standard) == nil, "good title passes")
        check(TitleCheck.problem("Flights", length: .standard) != nil, "one word is generic")
        check(TitleCheck.problem("Click the select button", length: .standard) != nil, "UI words rejected")
        check(TitleCheck.problem("One two three four five six seven eight nine ten eleven", length: .standard) != nil, "too long rejected")
        check(TitleCheck.stripped("IndiGo deals flights Select") == "IndiGo flights", "UI words stripped")
        check(TitleCheck.trimmed("a b c d e f g h i j k l m", length: .short).split(separator: " ").count == 8, "trimmed to the cap")
        check(Sanitizer.restoreProperNames("Flights to chennai", source: "Nashik to Chennai\\nFlights to Chennai today") == "Flights to Chennai", "place name capital restored")
    }

    static func listing() {
        let indigo = "IndiGo\n16 deals from\n16:20 | 4h | 20:20 | ₴10,714\nISK | 1 stop BLR | MAA\nSelect →\n17 deals from\n14:20 | 8h 40 | 23:00 | ₴10,487\nISK | 1 stop HYD | MAA\n"
        let f = ListingFacts.extract(from: indigo)
        check(f?.from == "ISK" && f?.to == "MAA", "route found: \(String(describing: f))")
        check(f?.cheapest == "₹10,487", "cheapest price with rupee sign: \(f?.cheapest ?? "nil")")
        check(f?.carrier == "IndiGo", "carrier: \(f?.carrier ?? "nil")")
        check(f?.title(length: .standard) == "IndiGo flights ISK to MAA from ₹10,487", "built title: \(f?.title(length: .standard) ?? "nil")")
        check(f?.isReflected(in: "IndiGo schedule") == false && f?.isReflected(in: "IndiGo flights ISK to MAA") == true, "route reflected check")
        let header = "Nashik (ISK) - Chennai (MAA) • 1 adult\n7 results\n16:20 | 20:20 | ₹10,714\nISK | MAA\n"
        let h = ListingFacts.extract(from: header)
        check(h?.fromCity == "Nashik" && h?.toCity == "Chennai", "cities from header: \(String(describing: h))")
        check(ListingFacts.extract(from: "Quarterly budget\nDepartment | Q1 | Q2\nTotal | 197,150") == nil, "ordinary text gives no facts")
        check(ListingFacts.extract(from: "CNC | PLC\nretrofit of machines") == nil, "two codes without times are not a route")
    }
}
