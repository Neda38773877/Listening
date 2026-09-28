import Foundation

/// How a transcript word was matched to a recognized (timed) word.
public enum LinkKind: String, Codable, Sendable {
    /// Same word.
    case exact
    /// Same spoken word, spelled differently (ending, typo, phonetic match).
    case similar
    /// Different word at the same position — one of the two transcriptions is wrong.
    case substituted
}

public struct AlignmentLink: Hashable, Sendable {
    public var recognizedIndex: Int
    public var kind: LinkKind
}

public struct AlignmentResult: Sendable {
    /// For every transcript word: the recognized word it was matched to.
    public var links: [AlignmentLink?]
    /// Recognized words that no transcript word was matched to (words the
    /// transcript is missing, or noise).
    public var unmatchedRecognized: [Int]

    public var matchedCount: Int { links.compactMap { $0 }.count }
}

/// Aligns the imported transcript with the recognizer output (a sequence
/// alignment, like diff). The recognizer output carries real audio timestamps, so
/// every aligned transcript word inherits a real timestamp.
///
/// For a one-hour meeting (~10 000 words on each side) a full O(n·m) matrix would
/// be too large, so the aligner first fixes long unique n-gram matches as anchors
/// and only runs dynamic programming in the small gaps between them.
public enum WordAligner {

    static let exactScore = 3
    static let similarScore = 1
    static let substituteScore = -1
    static let gapScore = -1
    /// Gaps up to this many DP cells are solved exactly; larger ones are split with more anchors.
    static let maxFullCells = 400_000

    public static func align(transcript: [String], recognized: [String]) -> AlignmentResult {
        let a = transcript.map(GermanText.normalize)
        let b = recognized.map(GermanText.normalize)
        var links = [AlignmentLink?](repeating: nil, count: a.count)

        var pairs: [(Int, Int)] = []
        solve(a, b, 0..<a.count, 0..<b.count, ngram: 3, into: &pairs)

        var usedB = Set<Int>()
        for (i, j) in pairs {
            let kind: LinkKind
            if a[i] == b[j] { kind = .exact } else if GermanText.soundsAlike(a[i], b[j]) { kind = .similar } else { kind = .substituted }
            links[i] = AlignmentLink(recognizedIndex: j, kind: kind)
            usedB.insert(j)
        }
        let unmatched = (0..<b.count).filter { !usedB.contains($0) }
        return AlignmentResult(links: links, unmatchedRecognized: unmatched)
    }

    // MARK: - Divide and conquer

    private static func solve(_ a: [String], _ b: [String], _ ra: Range<Int>, _ rb: Range<Int>,
                              ngram: Int, into out: inout [(Int, Int)]) {
        if ra.isEmpty || rb.isEmpty { return }
        if ra.count * rb.count <= maxFullCells {
            out.append(contentsOf: dp(a, b, ra, rb))
            return
        }
        // No distinctive shared words (very repetitive speech, or transcript and audio
        // do not correspond): align along the diagonal band only, and keep only pairs
        // that really match — never pair unrelated words here.
        if ngram == 0 {
            out.append(contentsOf: bandedDP(a, b, ra, rb).filter { a[$0.0] == b[$0.1] || GermanText.soundsAlike(a[$0.0], b[$0.1]) })
            return
        }
        let anchors = uniqueAnchors(a, b, ra, rb, n: ngram)
        if anchors.isEmpty {
            solve(a, b, ra, rb, ngram: ngram - 1, into: &out)
            return
        }
        var lastA = ra.lowerBound, lastB = rb.lowerBound
        for (i, j) in anchors {
            // Anchor n-grams may overlap; only take the part that moves strictly forward.
            if i < lastA || j < lastB { continue }
            solve(a, b, lastA..<i, lastB..<j, ngram: ngram, into: &out)
            var k = 0
            while k < max(ngram, 1), i + k < ra.upperBound, j + k < rb.upperBound, a[i + k] == b[j + k] {
                out.append((i + k, j + k))
                k += 1
            }
            lastA = i + k
            lastB = j + k
        }
        solve(a, b, lastA..<ra.upperBound, lastB..<rb.upperBound, ngram: ngram, into: &out)
    }

    /// N-grams that occur exactly once in both ranges, reduced to the longest
    /// chain that is increasing in both sequences.
    static func uniqueAnchors(_ a: [String], _ b: [String], _ ra: Range<Int>, _ rb: Range<Int>, n: Int) -> [(Int, Int)] {
        func grams(_ s: [String], _ r: Range<Int>) -> [String: Int] {
            var seen: [String: Int] = [:]
            guard r.count >= n else { return [:] }
            for i in r.lowerBound...(r.upperBound - n) {
                let slice = s[i..<(i + n)]
                // Skip grams made of very short words; they repeat too often to be reliable.
                if slice.reduce(0, { $0 + $1.count }) < 4 * n || slice.contains(where: \.isEmpty) { continue }
                let key = slice.joined(separator: " ")
                seen[key] = seen[key] == nil ? i : -1
            }
            return seen.filter { $0.value >= 0 }
        }
        let ga = grams(a, ra), gb = grams(b, rb)
        var cands: [(Int, Int)] = []
        for (k, i) in ga { if let j = gb[k] { cands.append((i, j)) } }
        cands.sort { $0.0 < $1.0 }
        return longestIncreasing(cands)
    }

    /// Longest subsequence strictly increasing in the second component (patience sorting).
    static func longestIncreasing(_ pairs: [(Int, Int)]) -> [(Int, Int)] {
        guard !pairs.isEmpty else { return [] }
        var tails: [Int] = []          // index into pairs
        var prev = [Int](repeating: -1, count: pairs.count)
        for (idx, p) in pairs.enumerated() {
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if pairs[tails[mid]].1 < p.1 { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 { prev[idx] = tails[lo - 1] }
            if lo == tails.count { tails.append(idx) } else { tails[lo] = idx }
        }
        var out: [(Int, Int)] = []
        var cur = tails.last ?? -1
        while cur >= 0 { out.append(pairs[cur]); cur = prev[cur] }
        return out.reversed()
    }

    // MARK: - Needleman–Wunsch

    /// Banded global alignment: only cells within `w` of the straight line from the
    /// start to the end of both ranges are evaluated, so memory is O(n·w).
    static func bandedDP(_ a: [String], _ b: [String], _ ra: Range<Int>, _ rb: Range<Int>) -> [(Int, Int)] {
        let n = ra.count, m = rb.count
        guard n > 0, m > 0 else { return [] }
        var w = max(100, abs(n - m) + 50)
        w = min(w, 6_000_000 / (2 * (n + 1)))
        // Rows must overlap, otherwise no path exists inside the band.
        if w < m / n + 2 { return [] }
        let width = 2 * w + 1
        let negInf = Int32.min / 4
        var score = [Int32](repeating: negInf, count: (n + 1) * width)
        var trace = [UInt8](repeating: 0, count: (n + 1) * width)
        func center(_ i: Int) -> Int { i * m / n }
        func slot(_ i: Int, _ j: Int) -> Int? {
            let o = j - center(i) + w
            return (o >= 0 && o < width && j >= 0 && j <= m) ? i * width + o : nil
        }
        for i in 0...n {
            let c = center(i)
            for j in max(0, c - w)...min(m, c + w) {
                guard let k = slot(i, j) else { continue }
                if i == 0 && j == 0 { score[k] = 0; continue }
                var best = negInf, dir: UInt8 = 0
                if i > 0, j > 0, let d = slot(i - 1, j - 1), score[d] > negInf {
                    let ai = a[ra.lowerBound + i - 1], bj = b[rb.lowerBound + j - 1]
                    let sub = ai == bj ? exactScore : (GermanText.soundsAlike(ai, bj) ? similarScore : substituteScore)
                    if score[d] + Int32(sub) > best { best = score[d] + Int32(sub); dir = 1 }
                }
                if i > 0, let u = slot(i - 1, j), score[u] > negInf, score[u] + Int32(gapScore) > best {
                    best = score[u] + Int32(gapScore); dir = 2
                }
                if j > 0, let l = slot(i, j - 1), score[l] > negInf, score[l] + Int32(gapScore) > best {
                    best = score[l] + Int32(gapScore); dir = 3
                }
                score[k] = best
                trace[k] = dir
            }
        }
        var out: [(Int, Int)] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            guard let k = slot(i, j) else { break }
            switch trace[k] {
            case 1: out.append((ra.lowerBound + i - 1, rb.lowerBound + j - 1)); i -= 1; j -= 1
            case 2: i -= 1
            case 3: j -= 1
            default: return out.reversed()
            }
        }
        return out.reversed()
    }

    /// Global alignment of a[ra] with b[rb]. Returns matched index pairs.
    static func dp(_ a: [String], _ b: [String], _ ra: Range<Int>, _ rb: Range<Int>) -> [(Int, Int)] {
        let n = ra.count, m = rb.count
        let cols = m + 1
        let negInf = Int32.min / 4
        var score = [Int32](repeating: negInf, count: (n + 1) * cols)
        // 1 = diagonal, 2 = up (skip a), 3 = left (skip b)
        var trace = [UInt8](repeating: 0, count: (n + 1) * cols)

        score[0] = 0
        if m >= 1 { for j in 1...m { score[j] = Int32(j * gapScore); trace[j] = 3 } }
        if n >= 1 {
            for i in 1...n {
                let ai = a[ra.lowerBound + i - 1]
                score[i * cols] = Int32(i * gapScore); trace[i * cols] = 2
                if m == 0 { continue }
                for j in 1...m {
                    let bj = b[rb.lowerBound + j - 1]
                    let sub: Int
                    if ai == bj { sub = exactScore } else if GermanText.soundsAlike(ai, bj) { sub = similarScore } else { sub = substituteScore }
                    var best = negInf, dir: UInt8 = 0
                    let d = score[(i - 1) * cols + j - 1]
                    if d + Int32(sub) > best { best = d + Int32(sub); dir = 1 }
                    let u = score[(i - 1) * cols + j]
                    if u + Int32(gapScore) > best { best = u + Int32(gapScore); dir = 2 }
                    let l = score[i * cols + j - 1]
                    if l + Int32(gapScore) > best { best = l + Int32(gapScore); dir = 3 }
                    score[i * cols + j] = best
                    trace[i * cols + j] = dir
                }
            }
        }

        var out: [(Int, Int)] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            let dir = trace[i * cols + j]
            if dir == 1 {
                out.append((ra.lowerBound + i - 1, rb.lowerBound + j - 1)); i -= 1; j -= 1
            } else if dir == 2 {
                i -= 1
            } else {
                j -= 1
            }
        }
        return out.reversed()
    }
}
