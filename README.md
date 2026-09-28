# Hören-Trainer — German meeting listening trainer (iPhone & iPad)

Learn German Hören and speaking from real work-meeting recordings. Import your Voice Memos audio files with transcripts, then tap any word to hear exactly that word in the original audio. Hören-Trainer aligns words to timestamps, suggests corrections, breaks meetings into sentences, teaches vocabulary with spaced repetition, and detects Redemittel (business phrases) to speed up your learning.

## What it does

- **Import media**: Voice Memos (.m4a, .mp3, .wav) + transcripts (.txt, .md, .srt, .vtt, .pdf) via Share › Open In, or pick files from the app.
- **On-device recognition**: Continuous on-device speech recognition in ~1-minute chunks, resumable across sessions. Audio never leaves the device unless you explicitly allow Apple server recognition in Settings.
- **Word-level alignment**: Aligns transcript words to recognized words with real timestamps. Approximate timings are clearly marked.
- **Correction suggestions**: Comparison of imported transcript with on-device speech recognition, shown with Original / Suggested / Confidence. Accept, edit, or reject each one. Original transcript preserved.
- **Sentence segmentation**: Automatic detection of sentence boundaries in the transcript.
- **Playback control**: Per-word and per-sentence playback with pre-roll. Variable speed 0.5–1.5× without pitch change.
- **Translation**: English and Persian translation via Apple on-device (when available) or Claude (external, opt-in).
- **Word cards**: Tap any word to hear exactly that occurrence (with ~180 ms pre-roll) and see its meaning (source shown: your word list, glossary, system dictionary, or Claude on request), the sentence from the meeting, and save it.
- **Vocabulary database**: Organized by category and custom topics. Seeded with PV/quality glossary.
- **Spaced repetition**: 9 review modes (German↔Persian, German↔English, Persian↔German, English↔German, audio recognition, fill-in-the-blank, multiple choice, sentence creation, speaking practice; plus mixed mode). SM-2 scheduling with Again/Hard/Good/Easy, prioritizing words frequent in your meetings, often missed, saved manually, and workplace categories.
- **Shadowing mode**: Record your voice and compare it with the original meeting audio.
- **Redemittel detection**: Highlights business phrases found in the meeting and recommends others you should practice.
- **Meeting vocabulary sources**: Vocabulary from multiple sources (A: heard in this meeting, B: related workplace vocabulary not necessarily heard, C: common meeting expressions recommended, D: technical vocabulary from your glossary, E: user-defined). B–D are never presented as if heard.
- **AI summary (optional, external)**: On request, Claude summarises the meeting; every statement must cite sentence numbers, unsupported statements are removed.
- **Timeline**: Automatic timeline generated from keyword detection.
- **Search**: Full-text search across all your meetings.
- **Dashboard**: Meetings processed, listening time, words saved and learned, repeatedly missed words, sentences practiced, shadowing repetitions, Redemittel learned, learning streak, 14-day listening chart, most common meeting vocabulary, weak vocabulary.
- **Custom dictionary**: Build your own dictionary with unlimited custom entries. Seeded with the PV/quality glossary from the web version.
- **Privacy and deletion**: All data stored on-device by default. You can delete a whole meeting, only its audio, all vocabulary, learning history, or all meetings.

## Accuracy & honesty rules

- **Timestamps only from recognition or user**: Never auto-corrected from guesses.
- **Explicitly unclear regions marked**: `[UNCLEAR]` marks where recognition confidence is very low.
- **Dictionary terms only suggested with audio evidence**: Never shown as if they were heard in the meeting.
- **Suggestions never shown as heard**: Always labelled as AI suggestions, never as recognized speech.
- **AI output labelled and validated**: Summaries, topics, and timelines are marked as AI-generated and checked against transcript.

## Privacy

- **On-device by default**: All processing, storage, and learning happens on your device.
- **External AI off by default**: Claude is opt-in per meeting. You control when external processing happens.
- **Text only over the wire**: Only the transcript text is sent to Claude, never audio.
- **Per-meeting consent**: The app asks for permission before any external request. You can disable Claude for individual meetings and reset permissions in Settings.
- **API key in Keychain**: Your Claude API key is stored securely in iOS Keychain, not synced to iCloud.
- **Apple server recognition opt-in**: On-device dictation is default; Apple's cloud recognition is optional.

## Architecture

MeetingCore package (pure Swift/Foundation logic, no UIKit/AVFoundation):

| Module | Purpose |
|--------|---------|
| Models.swift | MeetingDocument, Token (original + corrected text, WordTiming with source aligned/fuzzy/between/manual), Sentence, Correction, Topic, MeetingSummary, ProcessingState. |
| TranscriptParser.swift | Parse plain text, Markdown, SRT, WebVTT; strip timestamps & speaker labels without changing words (PDF text extraction via ImportService). |
| WordAligner.swift | Align transcript words to speech-recognition results with timestamps. |
| SentenceSegmenter.swift | Detect sentence boundaries and create segments. |
| CorrectionActions.swift | Apply correction suggestions and track changes. |
| SpacedRepetition.swift | SM-2 scheduling with Again/Hard/Good/Easy; review priority by overdue, meeting frequency, saved status, and category weight. |
| Redemittel.swift | Detect and recommend Redemittel (business phrases). |
| Search.swift | Full-text search over meetings and vocabularies. |
| VocabularyAnalyzer.swift | Extract content words, group by stem, categorize by source (A–E). |
| SummaryValidation.swift | Validate AI summaries against transcript evidence. |
| CustomDictionary.swift | Manage custom dictionary with arbitrary entries. |
| PlaybackPlanner.swift | Plan playback regions and pre-roll for words/sentences. |
| Shadowing.swift | Shadowing state machine: listen → pause to repeat → listen again → record → compare. |
| GermanText.swift | Normalisation, Levenshtein similarity, Kölner Phonetik, German function words. |
| MeetingBuilder.swift | Run parsing, assembly, segmentation and automatic topics on a document. |
| MeetingAssembler.swift | Turn transcript + recognized words into timed tokens and comparison suggestions. |

App (Views, Services, Persistence):

| Layer | Key files |
|-------|-----------|
| Views | RootView (main tab navigation), MeetingListView (library), MeetingWorkspaceView (editor), TranscriptView, PlayerBar, ImportSheet, SystemDictionaryView, FlowLayout (custom layout), ExternalAIConsent. |
| Services | AudioPlayer (playback control), SpeechRecognitionService (on-device recognition), OnDeviceTranslator (Apple Translation), ClaudeService (external AI), MeetingSession (in-memory state), ImportService (file import & parsing), AppSettings (user preferences), ProcessingPipeline (async coordination). |
| Persistence | Records.swift (SwiftData models), MeetingStore.swift (JSON document + audio files per meeting). |

## Build & run

**Requirements:**
- Mac with Xcode 16 or later.
- iOS 18 device or simulator.

**Steps:**

```bash
brew install xcodegen
xcodegen generate
open HoerenTrainer.xcodeproj
```

1. Select your signing team in Xcode (Signing & Capabilities).
2. On the device, enable German on-device dictation: Settings › General › Keyboard › Dictation languages. Add Deutsch (Germany).
3. Run the app on your device or simulator.

## Tests

**MeetingCore unit tests:**

```bash
cd Packages/MeetingCore
swift test
```

Covers:
- Transcript parsing (plain text, Markdown, SRT, WebVTT).
- Word alignment with a synthetic 12,000-word meeting with dropped and misheard words (performance and monotonicity).
- Correction actions and change tracking.
- Sentence segmentation.
- Spaced repetition scheduling and review modes.
- Redemittel detection and recommendation.
- Full-text search including accent-insensitive matching.
- Summary validation (evidence checking).
- Shadowing state machine.

**UI tests:**

Run via Xcode: Product › Test. Tests cover launch, tabs, and opening the import sheet.

**CI workflow:**

Push to any branch or open a pull request to trigger GitHub Actions:
- `core-tests`: Runs swift test on Packages/MeetingCore.
- `app-build`: Builds the app for the iOS Simulator.
- `app-ui-tests`: Runs UI tests on a simulated iPhone.
- `pv-analyzer`: Runs tests for the pv-analyzer Python tool.

## Known limitations

- **Persian translation**: On-device translation depends on Apple's Translation language availability. If not available, use the external Claude option or type your own translation.
- **Recognition quality**: Dependent on audio quality and background noise. Always review recognized text.
- **Word timing for missed words**: Words the recognizer skipped will have approximate timings based on neighbors. You can edit them manually.
- **Automatic timeline**: Uses keyword detection; AI topics are optional and require Claude consent.

## PV analyzer

A separate Python tool lives in `pv-analyzer/`. See `pv-analyzer/README.md` for details.

---

*Hören-Trainer is an iPhone and iPad app for learning German from real meetings. The earlier web prototype lives in `index.html`.*
