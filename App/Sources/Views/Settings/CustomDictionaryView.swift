import SwiftUI
import SwiftData
import MeetingCore

struct CustomDictionaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomTermRecord.term) private var terms: [CustomTermRecord]
    @State private var showImported = true
    @State private var searchText = ""
    @State private var newTerm = ""
    @State private var newCategory: TermCategory = .general
    @State private var showAddError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Quick add row
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Add name, machine, abbreviation…", text: $newTerm)
                            .textFieldStyle(.roundedBorder)
                        Menu {
                            Picker("Category", selection: $newCategory) {
                                ForEach(TermCategory.allCases, id: \.self) { cat in
                                    Text(cat.title).tag(cat)
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        Button("Add") {
                            addNewTerm()
                        }
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding()
                .background(Color(.systemGray6))

                // Search and toggle
                HStack {
                    SearchTextField(text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Imported", isOn: $showImported)
                        .labelsHidden()
                }
                .padding()

                // Terms list
                if filteredTerms.isEmpty {
                    ContentUnavailableView(
                        "No custom terms",
                        systemImage: "book.closed",
                        description: Text("Add names, machines, abbreviations, and other specialized terms.")
                    )
                } else {
                    List {
                        ForEach(groupedTerms, id: \.key) { category, items in
                            if !items.isEmpty {
                                Section(category) {
                                    ForEach(items) { term in
                                        termRow(term)
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
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Custom Dictionary")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func termRow(_ term: CustomTermRecord) -> some View {
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
        .padding(.vertical, 4)
    }

    private var filteredTerms: [CustomTermRecord] {
        terms.filter { term in
            let matchesSearch = searchText.isEmpty || [
                term.term, term.english, term.persian
            ].contains { $0.lowercased().contains(searchText.lowercased()) }

            let matchesImported = !showImported || !term.seeded

            return matchesSearch && matchesImported
        }
    }

    private var groupedTerms: [(key: String, value: [CustomTermRecord])] {
        let grouped = Dictionary(grouping: filteredTerms) { $0.category.title }
        return grouped.sorted { $0.key < $1.key }
    }

    private func addNewTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showAddError = true
            return
        }

        // Check for duplicates (case-insensitive)
        if terms.contains(where: { $0.term.lowercased() == trimmed.lowercased() }) {
            showAddError = true
            return
        }

        let term = CustomTermRecord(term: trimmed, category: newCategory, english: "", persian: "")
        modelContext.insert(term)
        try? modelContext.save()
        newTerm = ""
        newCategory = .general
        showAddError = false
    }
}

// MARK: - Search Text Field

struct SearchTextField: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
}
