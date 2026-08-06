//
//  String.swift
//  BilibiliLive
//
//  Created by whw on 2022/10/31.
//

import Foundation

extension String {
    static func += (lhs: inout String, rhs: Int) {
        if let number = Int(lhs) {
            lhs = String(number + rhs)
        }
    }

    static func -= (lhs: inout String, rhs: Int) {
        if let number = Int(lhs) {
            lhs = String(number - rhs)
        }
    }

    func isMatch(pattern: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        return regex.firstMatch(in: self, options: [], range: NSMakeRange(0, utf16.count)) != nil
    }

    func removingHTMLTags() -> String {
        return replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }

    /// Bilibili's app endpoints bake the unit into the cover text — "820观看",
    /// "1.2万弹幕", "-弹幕". The card already says which number is which with
    /// its own glyph, so the word is duplicated noise at 10 feet: keep the
    /// figure and drop the label. 万/亿 stay, since those are part of the
    /// number rather than a unit.
    ///
    /// Returns nil when nothing countable is left, so the server's "-"
    /// placeholder drops the whole item instead of rendering a bare dash.
    var statNumber: String? {
        let text = trimmingCharacters(in: .whitespaces)
        // A colon means a duration, not a labelled count — leave it whole.
        guard !text.contains(":") else { return text }
        // `isNumber` is category Nd/Nl/No, so CJK ideographs never match here
        // and the two magnitude marks have to be named explicitly.
        let figure = text.prefix { $0.isNumber || $0 == "." || $0 == "万" || $0 == "亿" }
        guard figure.contains(where: \.isNumber) else { return nil }
        return String(figure)
    }
}
