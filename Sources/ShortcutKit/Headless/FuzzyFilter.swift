/// Sublime-style fuzzy match: returns `nil` if the query characters can't be
/// found in order, otherwise returns a score (higher = better) and the
/// matched indices into the haystack. Case-insensitive.
enum FuzzyFilter {
    struct Match {
        let score: Int
        let matched: [Int]
    }

    static func match(query: String, in haystack: String) -> Match? {
        let qChars = Array(query.lowercased())
        let hChars = Array(haystack.lowercased())
        guard !qChars.isEmpty else { return Match(score: 0, matched: []) }

        var matched: [Int] = []
        matched.reserveCapacity(qChars.count)
        var qi = 0
        for (hi, ch) in hChars.enumerated() where qi < qChars.count {
            if ch == qChars[qi] {
                matched.append(hi)
                qi += 1
            }
        }
        guard qi == qChars.count else { return nil }
        return Match(score: score(haystack: hChars, matched: matched), matched: matched)
    }

    private static func score(haystack: [Character], matched: [Int]) -> Int {
        var score = matched.count * 5
        for i in 1 ..< matched.count where matched[i] == matched[i - 1] + 1 {
            score += 10
        }
        for idx in matched {
            if idx == 0 { score += 15; continue }
            let prev = haystack[idx - 1]
            if prev == " " || prev == "-" || prev == "_" || prev == "+" { score += 10 }
        }
        if let first = matched.first { score -= first }
        return score
    }
}
