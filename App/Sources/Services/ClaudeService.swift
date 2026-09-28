import Foundation
import MeetingCore

enum ExternalAIError: LocalizedError {
    case disabled
    case noAPIKey
    case noConsent
    case http(Int, String)
    case refused(String)
    case truncated
    case badResponse

    var errorDescription: String? {
        switch self {
        case .disabled: return "External AI is switched off. You can enable it in Settings › Privacy."
        case .noAPIKey: return "Add your Anthropic API key in Settings › Privacy to use external AI."
        case .noConsent: return "You have not allowed sending this meeting's transcript text."
        case .http(let code, let m): return "The AI service returned an error (\(code)): \(m)"
        case .refused(let m): return "The AI declined this request. \(m)"
        case .truncated: return "The AI response was cut off. Try a smaller batch."
        case .badResponse: return "The AI response could not be read."
        }
    }
}

/// External AI (Anthropic Claude) used only with explicit permission, only for text
/// (never audio), and only for: translations, word explanations, summary/topics.
/// Every output is labelled "Claude (external)" in the UI and validated before use.
struct ClaudeService {
    static let providerName = "Claude (external)"
    static let model = "claude-opus-5"

    let apiKey: String

    static func make(for meeting: UUID?, settings: AppSettings = .shared) throws -> ClaudeService {
        guard settings.externalAIEnabled else { throw ExternalAIError.disabled }
        guard let key = Keychain.read("anthropicAPIKey"), !key.isEmpty else { throw ExternalAIError.noAPIKey }
        if let m = meeting, !settings.hasConsent(for: m) { throw ExternalAIError.noConsent }
        return ClaudeService(apiKey: key)
    }

    // MARK: - Raw request

    /// Sends one Messages API request with a JSON-schema constrained answer and decodes it.
    func structured<T: Decodable>(_ type: T.Type, system: String, prompt: String, schema: [String: Any], maxTokens: Int = 16000) async throws -> T {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Server-side fallback: if a request is declined by a safety classifier, the API retries it on a fallback model.
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": maxTokens,
            "fallbacks": "default",
            "system": system,
            "messages": [["role": "user", "content": prompt]],
            "output_config": ["format": ["type": "json_schema", "schema": schema]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ExternalAIError.badResponse }
        guard code == 200 else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            throw ExternalAIError.http(code, message)
        }
        let stop = json["stop_reason"] as? String
        if stop == "refusal" {
            let details = (json["stop_details"] as? [String: Any])?["explanation"] as? String ?? ""
            throw ExternalAIError.refused(details)
        }
        if stop == "max_tokens" { throw ExternalAIError.truncated }
        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let payload = text.data(using: .utf8) else { throw ExternalAIError.badResponse }
        return try JSONDecoder().decode(T.self, from: payload)
    }

    // MARK: - Sentence translation

    struct TranslationItem: Decodable { let id: Int; let english: String; let persian: String; let uncertain: Bool }
    struct TranslationBatch: Decodable { let items: [TranslationItem] }

    static let translationSystem = """
    You translate German workplace-meeting sentences (quality, production, photovoltaics, engineering) into English and Persian for a language learner.
    Rules:
    - Translate exactly what the German says. Do not add, complete or guess missing content. Keep the fragmentary style of spoken German if the sentence is incomplete.
    - English: natural and technically accurate.
    - Persian: natural, fluent Persian (not word-for-word). Keep technical terms, product names, machine names, abbreviations and people's names as they are (you may add a Persian gloss in parentheses for technical terms).
    - "[UNCLEAR]" in the German marks an inaudible word; keep it as [UNCLEAR] in both translations.
    - Set "uncertain" to true if the German is garbled or ambiguous enough that the translation may be wrong.
    """

    func translate(_ sentences: [(id: Int, german: String)], glossary: [CustomTerm]) async throws -> [TranslationItem] {
        let terms = glossary.prefix(80).map { t in
            [t.term, t.english.map { "EN: \($0)" }, t.persian.map { "FA: \($0)" }].compactMap { $0 }.joined(separator: " | ")
        }.joined(separator: "\n")
        let lines = sentences.map { "\($0.id)\t\($0.german)" }.joined(separator: "\n")
        let prompt = """
        \(terms.isEmpty ? "" : "User glossary (use these meanings when the term occurs):\n\(terms)\n\n")Translate each line (format: id<TAB>German). Return every id exactly once.

        \(lines)
        """
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["items"],
            "properties": ["items": ["type": "array", "items": [
                "type": "object", "additionalProperties": false, "required": ["id", "english", "persian", "uncertain"],
                "properties": ["id": ["type": "integer"], "english": ["type": "string"], "persian": ["type": "string"], "uncertain": ["type": "boolean"]],
            ]]],
        ]
        let batch = try await structured(TranslationBatch.self, system: Self.translationSystem, prompt: prompt, schema: schema)
        let valid = Set(sentences.map(\.id))
        return batch.items.filter { valid.contains($0.id) }
    }

    // MARK: - Word explanation

    struct WordInfo: Decodable {
        let lemma: String
        let partOfSpeech: String
        let english: String
        let persian: String
        let synonyms: [String]
        let note: String
        let certain: Bool
    }

    func explain(word: String, sentence: String) async throws -> WordInfo {
        let system = """
        You explain one German word from a real workplace meeting to a learner, based on its meaning in the given sentence.
        Give the dictionary form, the part of speech, short English and Persian meanings (natural Persian), and up to 3 German synonyms that fit this context (empty list if none fit).
        If the word looks like a transcription error, is a name, or you are not sure of its meaning, say so in "note" and set "certain" to false. Never invent a meaning.
        """
        let prompt = "Word: \(word)\nSentence: \(sentence)"
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "required": ["lemma", "partOfSpeech", "english", "persian", "synonyms", "note", "certain"],
            "properties": [
                "lemma": ["type": "string"], "partOfSpeech": ["type": "string"], "english": ["type": "string"],
                "persian": ["type": "string"], "synonyms": ["type": "array", "items": ["type": "string"]],
                "note": ["type": "string"], "certain": ["type": "boolean"],
            ],
        ]
        return try await structured(WordInfo.self, system: system, prompt: prompt, schema: schema, maxTokens: 4000)
    }

    // MARK: - Summary and topics

    struct RawItem: Decodable { let text: String; let evidence: [Int] }
    struct RawSection: Decodable {
        let topic: String
        let discussed, problems, causes, actions, responsible, deadlines, decisions, openQuestions: [RawItem]
    }
    struct RawTopic: Decodable { let title: String; let firstSentence: Int; let lastSentence: Int }
    struct RawAnalysis: Decodable { let topics: [RawTopic]; let sections: [RawSection] }

    func analyze(_ doc: MeetingDocument) async throws -> (MeetingSummary, [Topic]) {
        let system = """
        You analyse the transcript of a German workplace meeting for a learner. Each line is "[sentence number] (time) text".
        Strict rules:
        - Only report what is actually said in the transcript. Do not infer, guess or add outside knowledge.
        - Every item must cite the sentence numbers that support it in "evidence". Items without evidence will be discarded.
        - "responsible" items must name a person exactly as named in the transcript; if nobody is named, leave the list empty.
        - Leave a list empty when the meeting does not clearly state it.
        - Write item texts in simple English, quoting key German words in quotes where helpful.
        - Topics: contiguous sentence ranges in order covering the meeting, with short German titles taken from the words used.
        """
        let lines = doc.sentences.enumerated().map { i, s -> String in
            let t = doc.timeRange(of: s).map { TimeFormat.short($0.lowerBound) } ?? "--:--"
            return "[\(i)] (\(t)) \(doc.text(of: s))"
        }.joined(separator: "\n")
        let item: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["text", "evidence"],
            "properties": ["text": ["type": "string"], "evidence": ["type": "array", "items": ["type": "integer"]]],
        ]
        let list: [String: Any] = ["type": "array", "items": item]
        let fields = ["discussed", "problems", "causes", "actions", "responsible", "deadlines", "decisions", "openQuestions"]
        var sectionProps: [String: Any] = ["topic": ["type": "string"]]
        for f in fields { sectionProps[f] = list }
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["topics", "sections"],
            "properties": [
                "topics": ["type": "array", "items": [
                    "type": "object", "additionalProperties": false, "required": ["title", "firstSentence", "lastSentence"],
                    "properties": ["title": ["type": "string"], "firstSentence": ["type": "integer"], "lastSentence": ["type": "integer"]],
                ]],
                "sections": ["type": "array", "items": [
                    "type": "object", "additionalProperties": false, "required": ["topic"] + fields, "properties": sectionProps,
                ]],
            ],
        ]
        let raw = try await structured(RawAnalysis.self, system: system, prompt: lines, schema: schema, maxTokens: 16000)
        func conv(_ items: [RawItem]) -> [EvidencedItem] { items.map { EvidencedItem(text: $0.text, evidence: $0.evidence) } }
        let sections = raw.sections.map {
            SummarySection(topic: $0.topic, discussed: conv($0.discussed), problems: conv($0.problems), causes: conv($0.causes),
                           actions: conv($0.actions), responsible: conv($0.responsible), deadlines: conv($0.deadlines),
                           decisions: conv($0.decisions), openQuestions: conv($0.openQuestions))
        }
        let summary = SummaryValidator.validate(MeetingSummary(sections: sections, provider: Self.providerName),
                                                sentenceCount: doc.sentences.count,
                                                transcript: doc.sentences.map { doc.text(of: $0) }.joined(separator: " "))
        let topics = SummaryValidator.validate(raw.topics.enumerated().map {
            Topic(id: $0.offset, title: $0.element.title, firstSentence: $0.element.firstSentence,
                  lastSentence: $0.element.lastSentence, provenance: .ai)
        }, sentenceCount: doc.sentences.count)
        return (summary, topics)
    }
}
