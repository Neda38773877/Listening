import Foundation

public enum TermCategory: String, Codable, Sendable, CaseIterable {
    case person, company, machine, process, abbreviation, pv, quality, product, general

    public var title: String {
        switch self {
        case .person: return "Name / colleague"
        case .company: return "Company term"
        case .machine: return "Machine"
        case .process: return "Process"
        case .abbreviation: return "Abbreviation"
        case .pv: return "PV terminology"
        case .quality: return "Quality terminology"
        case .product: return "Product"
        case .general: return "General"
        }
    }
}

/// A user-defined term (name, machine, abbreviation, …).
public struct CustomTerm: Codable, Hashable, Sendable {
    public var term: String
    public var category: TermCategory
    public var english: String?
    public var persian: String?

    public init(term: String, category: TermCategory, english: String? = nil, persian: String? = nil) {
        self.term = term
        self.category = category
        self.english = english
        self.persian = persian
    }
}

/// Lookup structure over the user's custom terms. Used to (1) give the speech
/// recognizer contextual hints and (2) protect/flag terms during correction.
/// It never rewrites text by itself.
public struct CustomDictionary: Sendable {
    public private(set) var terms: [CustomTerm]
    private var byKey: [String: CustomTerm] = [:]
    private var byPhonetic: [String: [CustomTerm]] = [:]

    public init(terms: [CustomTerm] = []) {
        self.terms = terms
        for t in terms {
            let k = GermanText.normalize(t.term)
            guard !k.isEmpty else { continue }
            byKey[k] = t
            let p = GermanText.colognePhonetic(k)
            if k.count >= 4 && !p.isEmpty { byPhonetic[p, default: []].append(t) }
        }
    }

    public func exact(_ word: String) -> CustomTerm? {
        byKey[GermanText.normalize(word)]
    }

    /// A dictionary term that sounds like `word` (but is not spelled the same).
    public func soundAlike(_ word: String) -> CustomTerm? {
        let k = GermanText.normalize(word)
        guard k.count >= 4 else { return nil }
        if byKey[k] != nil { return nil }
        let candidates = byPhonetic[GermanText.colognePhonetic(k)] ?? []
        return candidates.first { GermanText.similarity(GermanText.normalize($0.term), k) >= 0.5 }
    }

    /// Terms for the recognizer's contextual strings (single words and short phrases).
    public var contextualStrings: [String] {
        terms.map(\.term).filter { !$0.isEmpty && $0.count <= 40 }
    }
}
