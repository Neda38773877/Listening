import SwiftUI
import SwiftData
import MeetingCore

struct CustomDictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomTermRecord.term) private var terms: [CustomTermRecord]
    @State private var showImported = true
    @State private var searchText = ""
    @State private var editingTerm: CustomTermRecord?
    @State private var showAddError = false
    @State private var errorMessage = ""

    var body: some View {
        Form {
            Section("Quick add") {
                HStack(spacing: 8) {
                    TextField("Add name, machine, abbreviation…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Menu {
                        Picker("Category", selection: $searchText) {
                            ForEach(TermCategory.allCases, id: \.self) { cat in
                                Text(cat.title).tag(cat.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    Button("Add") {
                        // Quick add would go here
                    }
                    .disabled(searchText.isEmpty)
                }
            }

            Section("All terms") {
                HStack {
                    Text("Show imported glossary")
                    Spacer()
                    Toggle("", isOn: $showImported)
                        .labelsHidden()
                }
                .searchable(text: $searchText, prompt: "Search terms")
            }

            if filteredTerms.isEmpty {
                Text("No custom terms")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedTerms, id: \.key) { category, items in
                    if !items.isEmpty {
                        Section(category) {
                            ForEach(items) { term in
                                Button(action: { editingTerm = term }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(term.term)
                                                    .font(.headline)
                                                Spacer()
                                                if term.seeded {
                                                    Text("imported")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            HStack(spacing: 8) {
                                                if !term.english.isEmpty {
                                                    Text(term.english)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                if !term.persian.isEmpty {
                                                    Text(term.persian)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .environment(\.layoutDirection, .rightToLeft)
                                                }
                                            }
                                        }
                                        Spacer()
                                    }
                                    .foregroundStyle(.primary)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(term)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Text("Used as speech-recognition hints and to protect names and terms during correction. Terms are only suggested when the audio sounds like them — never inserted automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Custom Dictionary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTerm) { term in
            TermEditorSheet(term: term)
        }
    }

    private var filteredTerms: [CustomTermRecord] {
        terms.filter { term in
            let matchesSearch = searchText.isEmpty || [
                term.term, term.english, term.persian
            ].contains { $0.lowercased().contains(searchText.lowercased()) }

            let matchesImported = showImported || !term.seeded

            return matchesSearch && matchesImported
        }
    }

    private var groupedTerms: [(key: String, value: [CustomTermRecord])] {
        let grouped = Dictionary(grouping: filteredTerms) { $0.category.title }
        return grouped.sorted { $0.key < $1.key }
    }
}

// MARK: - Term Editor Sheet

struct TermEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var term: CustomTermRecord
    @Query(sort: \CustomTermRecord.term) private var allTerms: [CustomTermRecord]
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Term", text: $term.term)
                Picker("Category", selection: $term.categoryRaw) {
                    ForEach(TermCategory.allCases, id: \.self) { cat in
                        Text(cat.title).tag(cat.rawValue)
                    }
                }
                TextField("English", text: $term.english)
                TextField("Persian", text: $term.persian)
                    .environment(\.layoutDirection, .rightToLeft)

                if showError {
                    Text("This term already exists")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit Term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = term.term.trimmingCharacters(in: .whitespaces)
                        if allTerms.contains(where: { $0.id != term.id && $0.term.lowercased() == trimmed.lowercased() }) {
                            showError = true
                        } else {
                            try? modelContext.save()
                            dismiss()
                        }
                    }
                    .disabled(term.term.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
