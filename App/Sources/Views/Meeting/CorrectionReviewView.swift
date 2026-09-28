import SwiftUI
import MeetingCore

struct CorrectionReviewView: View {
    @ObservedObject var session: MeetingSession
    @Environment(\.dismiss) var dismiss

    @State private var filterStatus: FilterStatus = .pending
    @State private var editingCorrectionID: Int?
    @State private var editText: String = ""
    @State private var showAcceptAllConfirmation = false

    enum FilterStatus {
        case pending
        case accepted
        case rejected
        case all
    }

    var filteredCorrections: [Correction] {
        let corrections = session.doc.corrections
        switch filterStatus {
        case .pending:
            return corrections.filter { $0.status == .pending }
                .sorted { $0.confidence > $1.confidence || ($0.confidence == $1.confidence && $0.tokenID < $1.tokenID) }
        case .accepted:
            return corrections.filter { $0.status == .accepted || $0.status == .edited }
                .sorted { $0.confidence > $1.confidence || ($0.confidence == $1.confidence && $0.tokenID < $1.tokenID) }
        case .rejected:
            return corrections.filter { $0.status == .rejected }
                .sorted { $0.confidence > $1.confidence || ($0.confidence == $1.confidence && $0.tokenID < $1.tokenID) }
        case .all:
            return corrections.sorted { $0.confidence > $1.confidence || ($0.confidence == $1.confidence && $0.tokenID < $1.tokenID) }
        }
    }

    var pendingHighConfidence: [Correction] {
        session.doc.corrections.filter {
            $0.status == .pending && $0.confidence == .high && ($0.kind == .replace || $0.kind == .insert)
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                Text("Nothing is changed until you accept. The original transcript is always kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()

                Picker("Filter", selection: $filterStatus) {
                    Text("Pending").tag(FilterStatus.pending)
                    Text("Accepted").tag(FilterStatus.accepted)
                    Text("Rejected").tag(FilterStatus.rejected)
                    Text("All").tag(FilterStatus.all)
                }
                .pickerStyle(.segmented)
                .padding()

                if filteredCorrections.isEmpty {
                    ContentUnavailableView("No corrections to review", systemImage: "checkmark.circle.fill")
                } else {
                    List {
                        ForEach(filteredCorrections, id: \.id) { correction in
                            correctionRow(correction)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Review Corrections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !pendingHighConfidence.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Accept all High") {
                            showAcceptAllConfirmation = true
                        }
                        .confirmationDialog(
                            "Accept \(pendingHighConfidence.count) high-confidence suggestions?",
                            isPresented: $showAcceptAllConfirmation
                        ) {
                            Button("Accept all") {
                                for c in pendingHighConfidence {
                                    session.doc.accept(correction: c.id)
                                }
                                session.changed()
                            }
                        }
                    }
                }
            }
        }
    }

    private func correctionRow(_ correction: Correction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Correction kind and text
            switch correction.kind {
            case .replace:
                Text("Original transcript: \(correction.original)")
                    .strikethrough(correction.status == .accepted || correction.status == .edited)
                Text("Suggested: \(correction.suggested)")
                    .fontWeight(.semibold)

            case .insert:
                Text("Heard but missing from the transcript: \(correction.suggested)")

            case .unverified:
                Text("Could not be verified in the audio: \(correction.original)")
            }

            // Confidence badge
            HStack(spacing: 12) {
                confidenceBadge(correction.confidence)

                // Reason and context
                VStack(alignment: .leading, spacing: 2) {
                    Text(correction.reason)
                        .font(.caption)

                    if let sentenceIndex = session.doc.sentenceIndex(containingToken: correction.tokenID) {
                        Text(session.doc.text(of: session.doc.sentences[sentenceIndex]))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer()
            }

            // Action buttons
            HStack(spacing: 8) {
                // Play button (if timing exists)
                if session.doc.tokens.indices.contains(correction.tokenID),
                   session.doc.tokens[correction.tokenID].timing != nil {
                    Button(action: { session.playWord(correction.tokenID) }) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                if correction.status == .pending {
                    if correction.kind == .unverified {
                        Button("Keep") {
                            session.doc.edit(correction: correction.id, text: correction.original)
                            session.changed()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Button("Edit") {
                            editText = correction.original
                            editingCorrectionID = correction.id
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Button("Mark [UNCLEAR]") {
                            session.doc.edit(correction: correction.id, text: Correction.unclearMarker)
                            session.changed()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    } else {
                        Button("Accept") {
                            session.doc.accept(correction: correction.id)
                            session.changed()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Button("Edit") {
                            editText = correction.suggested
                            editingCorrectionID = correction.id
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Button("Reject", role: .destructive) {
                            session.doc.reject(correction: correction.id)
                            session.changed()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                } else {
                    Text(correction.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Undo") {
                        session.doc.reopen(correction: correction.id)
                        session.changed()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.vertical, 8)
        .alert("Edit correction", isPresented: Binding(
            get: { editingCorrectionID == correction.id },
            set: { if !$0 { editingCorrectionID = nil } }
        )) {
            TextField("New text", text: $editText)
            Button("Save") {
                session.doc.edit(correction: correction.id, text: editText)
                session.changed()
                editingCorrectionID = nil
            }
            Button("Cancel", role: .cancel) { editingCorrectionID = nil }
        }
    }

    private func confidenceBadge(_ confidence: Confidence) -> some View {
        Text(confidence.label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(confidenceColor(confidence))
            .foregroundStyle(.white)
            .cornerRadius(4)
    }

    private func confidenceColor(_ confidence: Confidence) -> Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}
