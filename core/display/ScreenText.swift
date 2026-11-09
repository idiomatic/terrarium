import Foundation
import Vision

/// The text on a screenshot, for a recipe that answers a console's questions as they appear instead of at times measured on
/// another Mac.
enum ScreenText {
    /// What Vision reads in a PNG: lowercase, with every run of whitespace as one space. Empty if it reads nothing.
    static func read(png: Data) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // The words are a prompt's, not prose: correction would "fix" a path or a password prompt.
        request.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(data: png).perform([request])) != nil else { return "" }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: " ").lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Letters, digits, and the marks a prompt ends with, from `text`: case, spacing, and other punctuation do not count.
    private static func compact(_ text: String) -> [Character] {
        text.lowercased().filter { $0.isLetter || $0.isNumber || ":@#".contains($0) }.map { $0 }
    }

    /// Whether `screen` shows `needle`, allowing for what an OCR of a small bitmap font gets wrong ("Passuord: -"): spaces and
    /// case are ignored, and a phrase may differ in a character (from 8 up; two, from 12). An approximate substring match.
    static func shows(_ needle: String, in screen: String) -> Bool {
        let pattern = compact(needle), text = compact(screen)
        guard !pattern.isEmpty else { return true }
        let allowed = pattern.count >= 12 ? 2 : pattern.count >= 8 ? 1 : 0
        // Sellers' algorithm: the least edits to turn the pattern into a substring of the text, ending at each position.
        var column = Array(0...pattern.count)
        for character in text {
            var diagonal = column[0]
            column[0] = 0
            for row in 1...pattern.count {
                let above = column[row]
                column[row] = min(column[row] + 1, column[row - 1] + 1, diagonal + (pattern[row - 1] == character ? 0 : 1))
                diagonal = above
            }
            if column[pattern.count] <= allowed { return true }
        }
        return false
    }
}
