import Foundation

public enum RedemittelCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case openingTopic, introducingProblem, describingProblem, explainingCause, givingExample, askingClarification
    case agreeing, disagreeing, suggestion, request, responsibility, deadlines, priorities, progress
    case measurements, qualityProblems, productionProblems, makingDecision, confirmingDecision, closingTopic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openingTopic: return "Opening a topic"
        case .introducingProblem: return "Introducing a problem"
        case .describingProblem: return "Describing a problem"
        case .explainingCause: return "Explaining a cause"
        case .givingExample: return "Giving an example"
        case .askingClarification: return "Asking for clarification"
        case .agreeing: return "Agreeing"
        case .disagreeing: return "Disagreeing"
        case .suggestion: return "Making a suggestion"
        case .request: return "Making a request"
        case .responsibility: return "Assigning responsibility"
        case .deadlines: return "Talking about deadlines"
        case .priorities: return "Talking about priorities"
        case .progress: return "Reporting progress"
        case .measurements: return "Discussing measurements"
        case .qualityProblems: return "Discussing quality problems"
        case .productionProblems: return "Discussing production problems"
        case .makingDecision: return "Making decisions"
        case .confirmingDecision: return "Confirming decisions"
        case .closingTopic: return "Closing a topic"
        }
    }
}

/// A detection pattern. `regex` runs case-insensitively on the sentence text;
/// `pattern` is the learnable form shown to the user ("Das Problem ist, dass …").
public struct RedemittelPattern: Sendable, Hashable {
    public var category: RedemittelCategory
    public var pattern: String
    public var regex: String
    public var english: String
    public var persian: String
}

/// An expression that actually occurs in the meeting transcript.
public struct RedemittelHit: Codable, Hashable, Sendable {
    public var category: RedemittelCategory
    public var pattern: String
    /// The exact words from the transcript that matched.
    public var matchedText: String
    public var sentenceIndex: Int
}

public enum RedemittelCatalog {

    static func p(_ c: RedemittelCategory, _ pattern: String, _ regex: String, _ en: String, _ fa: String) -> RedemittelPattern {
        RedemittelPattern(category: c, pattern: pattern, regex: regex, english: en, persian: fa)
    }

    /// Patterns used to *find* expressions in real meetings.
    public static let patterns: [RedemittelPattern] = [
        p(.openingTopic, "Kommen wir zu …", #"\bkommen wir (jetzt |nun |mal )?(zu|zum|zur)\b"#, "Let's move on to …", "برسیم به …"),
        p(.openingTopic, "Der nächste Punkt ist …", #"\b(der )?nächste(r)? punkt\b"#, "The next point is …", "مورد بعدی …"),
        p(.openingTopic, "Es geht um …", #"\bes geht (hier |jetzt |heute )?um\b"#, "It's about …", "موضوع دربارهٔ … است"),
        p(.openingTopic, "Ich wollte kurz … ansprechen", #"\bansprechen\b"#, "I wanted to briefly raise …", "می‌خواستم … را مطرح کنم"),
        p(.openingTopic, "Zum Thema …", #"\bzum thema\b"#, "On the topic of …", "در مورد موضوع …"),

        p(.introducingProblem, "Das Problem ist, dass …", #"\bdas problem ist\b"#, "The problem is that …", "مشکل این است که …"),
        p(.introducingProblem, "Wir haben ein Problem mit …", #"\b(wir haben|es gibt) (ein|einen|das|noch ein) (problem|fehler)\b"#, "We have a problem with …", "با … مشکل داریم"),
        p(.introducingProblem, "Mir ist aufgefallen, dass …", #"\b(mir ist|uns ist) (\w+ )?aufgefallen\b"#, "I noticed that …", "متوجه شدم که …"),
        p(.introducingProblem, "Es gab Probleme mit …", #"\bes gab (\w+ )?(probleme|schwierigkeiten)\b"#, "There were problems with …", "با … مشکلاتی وجود داشت"),

        p(.describingProblem, "… funktioniert nicht richtig", #"\bfunktioniert (\w+ )?nicht\b"#, "… doesn't work properly", "… درست کار نمی‌کند"),
        p(.describingProblem, "Der Fehler tritt auf, wenn …", #"\btritt (\w+ )?auf\b|\baufgetreten\b"#, "The error occurs when …", "خطا وقتی رخ می‌دهد که …"),
        p(.describingProblem, "Das passiert immer wieder", #"\b(passiert|kommt) (\w+ )?immer wieder\b"#, "That keeps happening", "این مدام اتفاق می‌افتد"),

        p(.explainingCause, "Das liegt daran, dass …", #"\bliegt (\w+ )?daran\b"#, "That's because …", "دلیلش این است که …"),
        p(.explainingCause, "Der Grund ist …", #"\bder grund (ist|war|dafür)\b"#, "The reason is …", "دلیلش … است"),
        p(.explainingCause, "… weil …", #"\bweil\b"#, "… because …", "… چون …"),
        p(.explainingCause, "Das kommt von …", #"\bdas kommt (\w+ )?(von|vom|daher)\b"#, "That comes from …", "این از … می‌آید"),
        p(.explainingCause, "… ist darauf zurückzuführen", #"\bzurückzuführen\b"#, "… can be traced back to …", "… به … برمی‌گردد"),

        p(.givingExample, "Zum Beispiel …", #"\bzum beispiel\b|\bz\. ?b\."#, "For example …", "برای مثال …"),
        p(.givingExample, "Wie bei …", #"\bwie (zum beispiel )?bei\b"#, "As with …", "مثل مورد …"),

        p(.askingClarification, "Was meinst du mit …?", #"\bwas meinst (du|ihr|sie)\b"#, "What do you mean by …?", "منظورت از … چیست؟"),
        p(.askingClarification, "Kannst du das noch mal erklären?", #"\b(noch ?mal|nochmal) erklären\b"#, "Can you explain that again?", "می‌توانی دوباره توضیح بدهی؟"),
        p(.askingClarification, "Habe ich das richtig verstanden, dass …?", #"\brichtig verstanden\b"#, "Did I understand correctly that …?", "درست فهمیدم که …؟"),
        p(.askingClarification, "Wie genau …?", #"\bwie genau\b"#, "How exactly …?", "دقیقاً چطور …؟"),

        p(.agreeing, "Da hast du recht.", #"\b(da )?(hast du|haben sie|habt ihr) recht\b"#, "You're right there.", "حق با توست."),
        p(.agreeing, "Das sehe ich auch so.", #"\bsehe ich (auch )?so\b"#, "I see it the same way.", "من هم همین نظر را دارم."),
        p(.agreeing, "Einverstanden.", #"\beinverstanden\b"#, "Agreed.", "موافقم."),
        p(.agreeing, "Genau.", #"^genau\b"#, "Exactly.", "دقیقاً."),

        p(.disagreeing, "Da bin ich anderer Meinung.", #"\banderer meinung\b"#, "I see it differently.", "من نظر دیگری دارم."),
        p(.disagreeing, "Ich bin mir nicht sicher, ob …", #"\bnicht (so )?sicher,? ob\b"#, "I'm not sure whether …", "مطمئن نیستم که …"),
        p(.disagreeing, "Das sehe ich anders.", #"\bsehe ich (\w+ )?anders\b"#, "I see that differently.", "من این را طور دیگری می‌بینم."),
        p(.disagreeing, "Ja, aber …", #"^ja,? aber\b"#, "Yes, but …", "بله، اما …"),

        p(.suggestion, "Ich würde vorschlagen, dass …", #"\b(würde|möchte) (\w+ )?vorschlagen\b"#, "I would suggest that …", "پیشنهاد می‌کنم که …"),
        p(.suggestion, "Wie wäre es, wenn …?", #"\bwie wäre es\b"#, "How about …?", "چطور است که …؟"),
        p(.suggestion, "Wir könnten …", #"\bwir könnten\b"#, "We could …", "می‌توانیم …"),
        p(.suggestion, "Sollen wir …?", #"\bsollen wir\b"#, "Shall we …?", "… کنیم؟"),
        p(.suggestion, "Mein Vorschlag wäre …", #"\bvorschlag\b"#, "My suggestion would be …", "پیشنهاد من … است"),

        p(.request, "Kannst du bitte …?", #"\b(kannst du|könntest du|können sie|könnten sie|könnt ihr) (\w+ ){0,3}bitte\b|\bbitte\b"#, "Could you please …?", "لطفاً … می‌توانی؟"),
        p(.request, "Schick mir bitte …", #"\bschick(e|t)? (mir|uns) (\w+ )?bitte\b"#, "Please send me …", "لطفاً … را برایم بفرست"),

        p(.responsibility, "… kümmert sich darum", #"\bkümmer(t|st|n)? (\w+ )?(sich|mich|dich|uns) (\w+ )?(darum|um)\b"#, "… will take care of it", "… پیگیری‌اش را به عهده می‌گیرد"),
        p(.responsibility, "Wer übernimmt das?", #"\b(übernimmt|übernehme|übernehmen)\b"#, "Who takes this on?", "چه کسی این را به عهده می‌گیرد؟"),
        p(.responsibility, "… ist dafür zuständig", #"\b(zuständig|verantwortlich)\b"#, "… is responsible for it", "… مسئول آن است"),

        p(.deadlines, "bis Ende der Woche", #"\bbis (zum )?ende (der|des|dieser|nächster) (woche|monats|tages)\b"#, "by the end of the week", "تا آخر هفته"),
        p(.deadlines, "bis morgen / bis Freitag", #"\bbis (morgen|übermorgen|montag|dienstag|mittwoch|donnerstag|freitag|nächste woche)\b"#, "by tomorrow / by Friday", "تا فردا / تا جمعه"),
        p(.deadlines, "Das muss heute noch …", #"\bheute noch\b"#, "That still has to … today", "این باید همین امروز …"),
        p(.deadlines, "Die Deadline ist …", #"\b(deadline|frist|termin)\b"#, "The deadline is …", "مهلت … است"),
        p(.deadlines, "in KW …", #"\b(kw|kalenderwoche) ?\d{1,2}\b"#, "in calendar week …", "در هفتهٔ تقویمی …"),

        p(.priorities, "Das hat höchste Priorität.", #"\bpriorität\b"#, "That has top priority.", "این بالاترین اولویت را دارد."),
        p(.priorities, "Das ist dringend.", #"\b(dringend|eilig)\b"#, "That's urgent.", "این فوری است."),
        p(.priorities, "Zuerst müssen wir …", #"\b(zuerst|als erstes|vorrangig) (müssen|sollten|machen)\b"#, "First we need to …", "اول باید …"),

        p(.progress, "Wir sind gerade dabei, …", #"\b(sind|bin) (\w+ )?dabei\b"#, "We are currently working on …", "در حال … هستیم"),
        p(.progress, "… ist schon erledigt", #"\b(erledigt|abgeschlossen|fertig)\b"#, "… is already done", "… انجام شده است"),
        p(.progress, "Stand ist …", #"\b(der )?(aktuelle )?stand\b"#, "The current status is …", "وضعیت فعلی …"),
        p(.progress, "Wir haben … geschafft", #"\bgeschafft\b"#, "We managed to …", "توانستیم …"),

        p(.measurements, "Wir haben … gemessen", #"\b(gemessen|messung|messungen|messwert|messwerte)\b"#, "We measured …", "… را اندازه گرفتیم"),
        p(.measurements, "Die Werte liegen bei …", #"\b(liegt|liegen) (\w+ )?bei\b"#, "The values are around …", "مقادیر حدود … است"),
        p(.measurements, "… außerhalb der Toleranz", #"\b(toleranz|grenzwert|spezifikation|abweichung)\b"#, "… outside the tolerance", "… خارج از تلرانس"),
        p(.measurements, "Wir müssen die Kalibrierung prüfen", #"\bkalibrier\w*\b"#, "We need to check the calibration", "باید کالیبراسیون را بررسی کنیم"),

        p(.qualityProblems, "… ist nicht in Ordnung", #"\bnicht in ordnung\b"#, "… is not OK", "… مشکل دارد"),
        p(.qualityProblems, "Wir haben Reklamationen wegen …", #"\b(reklamation|reklamationen|ausschuss|nacharbeit)\b"#, "We have complaints about …", "به خاطر … شکایت داریم"),
        p(.qualityProblems, "Das ist ein Qualitätsproblem", #"\bqualität\w*\b"#, "That is a quality problem", "این یک مشکل کیفی است"),
        p(.qualityProblems, "Die Module sind defekt", #"\b(defekt|defekte|beschädigt|fehlerhaft)\b"#, "The modules are defective", "ماژول‌ها معیوب هستند"),

        p(.productionProblems, "Die Anlage steht", #"\b(anlage|linie|maschine) (\w+ )?steht\b|\bstillstand\b"#, "The line is down", "خط تولید متوقف است"),
        p(.productionProblems, "Wir haben einen Engpass bei …", #"\b(engpass|verzögerung|lieferverzug|rückstand)\b"#, "We have a bottleneck in …", "در … گلوگاه داریم"),
        p(.productionProblems, "Die Produktion läuft …", #"\bproduktion (\w+ )?läuft\b"#, "Production is running …", "تولید … در جریان است"),

        p(.makingDecision, "Wir machen es so: …", #"\bwir machen (das|es) so\b"#, "We'll do it like this: …", "این‌طور انجامش می‌دهیم: …"),
        p(.makingDecision, "Wir haben entschieden, dass …", #"\b(entschieden|entscheiden|entscheidung)\b"#, "We have decided that …", "تصمیم گرفتیم که …"),
        p(.makingDecision, "Wir einigen uns auf …", #"\b(einigen|geeinigt)\b"#, "We agree on …", "روی … توافق می‌کنیم"),

        p(.confirmingDecision, "Dann bleibt es dabei.", #"\bbleibt (es )?dabei\b"#, "Then that's settled.", "پس همین‌طور می‌ماند."),
        p(.confirmingDecision, "Also, wir halten fest: …", #"\b(halten|festhalten|festgehalten) (\w+ )?fest\b|\bfestgehalten\b"#, "So, to record: …", "پس ثبت می‌کنیم: …"),
        p(.confirmingDecision, "Passt das so?", #"\bpasst (das|es) (so|für)\b"#, "Is that OK like this?", "این‌طوری خوب است؟"),

        p(.closingTopic, "Dann machen wir hier Schluss.", #"\b(machen wir|mache ich) (\w+ )?schluss\b"#, "Let's stop here.", "همین‌جا تمامش کنیم."),
        p(.closingTopic, "Gibt es noch Fragen?", #"\b(gibt es|habt ihr|haben sie) noch (\w+ )?fragen\b"#, "Are there any more questions?", "سؤال دیگری هست؟"),
        p(.closingTopic, "Das war's von meiner Seite.", #"\bwar'?s (\w+ )?von (meiner|unserer) seite\b|\bvon meiner seite\b"#, "That's all from my side.", "از طرف من همین بود."),
        p(.closingTopic, "Danke euch!", #"\b(danke|vielen dank)\b"#, "Thank you all!", "ممنون از همه!"),
    ]

    /// Additional useful expressions that are *recommended* — never shown as if they
    /// were said in the meeting.
    public static let recommended: [RedemittelCategory: [String]] = [
        .openingTopic: ["Ich würde gern mit … anfangen.", "Als Nächstes würde ich gern über … sprechen."],
        .introducingProblem: ["Wir haben da ein Thema mit …", "Ich sehe da ein Risiko bei …"],
        .describingProblem: ["Das Problem tritt nur sporadisch auf.", "Seit letzter Woche beobachten wir …"],
        .explainingCause: ["Die Ursache ist noch unklar.", "Vermutlich hängt das mit … zusammen."],
        .givingExample: ["Ein Beispiel dafür ist …", "Nehmen wir mal …"],
        .askingClarification: ["Könntest du das bitte konkretisieren?", "Was heißt das konkret für uns?"],
        .agreeing: ["Das ist ein guter Punkt.", "Dem stimme ich zu."],
        .disagreeing: ["Da habe ich Bedenken.", "Ich sehe das etwas kritischer."],
        .suggestion: ["Mein Vorschlag wäre, dass …", "Wir sollten vielleicht …"],
        .request: ["Könntest du mir bitte … schicken?", "Ich bräuchte bitte noch …"],
        .responsibility: ["Wer kümmert sich darum?", "Ich übernehme das."],
        .deadlines: ["Bis wann brauchst du das?", "Schaffen wir das bis Freitag?"],
        .priorities: ["Was hat gerade Vorrang?", "Das können wir erst mal zurückstellen."],
        .progress: ["Wir liegen im Zeitplan.", "Da gibt es noch nichts Neues."],
        .measurements: ["Die Messwerte schwanken stark.", "Wir sollten die Messung wiederholen."],
        .qualityProblems: ["Wir müssen die Ursache genauer analysieren.", "Das ist ein Ausreißer."],
        .productionProblems: ["Wie viele Module sind betroffen?", "Wir müssen die Linie kurz anhalten."],
        .makingDecision: ["Lasst uns das so festlegen.", "Wir gehen erst mal so vor."],
        .confirmingDecision: ["Dann halten wir das so fest.", "Sind alle einverstanden?"],
        .closingTopic: ["Dann schließen wir das Thema ab.", "Danke, das war's für heute."],
    ]

    private static let compiled: [(RedemittelPattern, NSRegularExpression)] = patterns.compactMap { p in
        guard let re = try? NSRegularExpression(pattern: p.regex, options: [.caseInsensitive]) else { return nil }
        return (p, re)
    }

    /// Finds expressions in real sentences. The matched text is always copied from the transcript.
    public static func find(in sentences: [String]) -> [RedemittelHit] {
        var hits: [RedemittelHit] = []
        for (i, text) in sentences.enumerated() {
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            var seenCategories = Set<RedemittelCategory>()
            for (p, re) in compiled {
                guard let m = re.firstMatch(in: text, range: range) else { continue }
                // One hit per category per sentence keeps the list readable.
                if seenCategories.contains(p.category) { continue }
                seenCategories.insert(p.category)
                hits.append(RedemittelHit(category: p.category, pattern: p.pattern,
                                          matchedText: ns.substring(with: m.range), sentenceIndex: i))
            }
        }
        return hits
    }
}
