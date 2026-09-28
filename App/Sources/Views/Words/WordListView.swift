import SwiftUI
import SwiftData
import MeetingCore

struct WordListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var clips = ClipPlayer()
    @Query(sort: \VocabItem.dateAdded, order: .reverse) private var items: [VocabItem]
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var selectedStatus = "All"
    @State private var showAddSheet = false
    @State private var showCategoryManager = false
    @State private var deleteItem: VocabItem?

    var body: some View {
        NavigationStack {
            Group {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "No saved words",
                        systemImage: "character.book.closed",
                        description: Text("Tap a word in a meeting transcript and choose Save to Word List.")
                    )
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            NavigationLink(destination: WordDetailView(item: item)) {
                                wordRow(item)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteItem = item
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search words")
            .navigationTitle("Word List")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddSheet = true }) {
                        Label("Add", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Section("Category") {
                            ForEach(["All"] + allCategories, id: \.self) { cat in
                                Button(action: { selectedCategory = cat }) {
                                    HStack {
                                        Text(cat)
                                        if cat == selectedCategory {
                                            Label("", systemImage: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        Section("Status") {
                            ForEach(["All", "Learning", "Mastered", "Expressions", "Due now"], id: \.self) { status in
                                Button(action: { selectedStatus = status }) {
                                    HStack {
                                        Text(status)
                                        if status == selectedStatus {
                                            Label("", systemImage: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: { showCategoryManager = true }) {
                        Label("Categories", systemImage: "folder")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddWordSheet()
            }
            .sheet(isPresented: $showCategoryManager) {
                CategoryManagerView()
            }
            .confirmationDialog("Delete Word", isPresented: .constant(deleteItem != nil)) {
                Button("Delete", role: .destructive) {
                    if let item = deleteItem {
                        modelContext.delete(item)
                        try? modelContext.save()
                    }
                    deleteItem = nil
                }
                Button("Cancel", role: .cancel) {
                    deleteItem = nil
                }
            } message: {
                if let item = deleteItem {
                    Text("Delete \"\(item.german)\"?")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("\(filteredItems.count) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func wordRow(_ item: VocabItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.german)
                    .font(.headline)
                Spacer()
                if item.hasClip {
                    Button(action: { _ = clips.play(item: item) }) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack(spacing: 8) {
                if !item.english.isEmpty {
                    Text(item.english)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !item.persian.isEmpty {
                    Text(item.persian)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            HStack(spacing: 8) {
                if !item.category.isEmpty {
                    Label(item.category, systemImage: "tag")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !item.meetingTitle.isEmpty {
                    Text(item.meetingTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if item.due <= Date() && !item.mastered {
                    Label("Due", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var filteredItems: [VocabItem] {
        items.filter { item in
            let matchesSearch = searchText.isEmpty || [
                item.german, item.english, item.persian, item.notes
            ].contains { $0.lowercased().contains(searchText.lowercased()) }

            let matchesCategory = selectedCategory == "All" || item.category == selectedCategory

            let matchesStatus: Bool
            switch selectedStatus {
            case "Learning": matchesStatus = !item.mastered
            case "Mastered": matchesStatus = item.mastered
            case "Expressions": matchesStatus = item.isExpression
            case "Due now": matchesStatus = item.due <= Date() && !item.mastered
            default: matchesStatus = true
            }

            return matchesSearch && matchesCategory && matchesStatus
        }
    }

    private var allCategories: [String] {
        var cats = Set(items.map(\.category))
        cats.formUnion(VocabCategory.allCases.map(\.rawValue))
        let customCats = try? modelContext.fetch(FetchDescriptor<CustomCategory>())
        cats.formUnion(customCats?.map(\.name) ?? [])
        return cats.sorted()
    }
}

// MARK: - Add Word Sheet

struct AddWordSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var german = ""
    @State private var english = ""
    @State private var persian = ""
    @State private var category = VocabCategory.work.rawValue
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("German (required)", text: $german)
                TextField("English", text: $english)
                TextField("Persian", text: $persian)
                    .environment(\.layoutDirection, .rightToLeft)
                Picker("Category", selection: $category) {
                    ForEach(VocabCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat.rawValue)
                    }
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...)
            }
            .navigationTitle("Add Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let item = VocabItem(german: german, category: category, savedManually: true)
                        item.english = english
                        item.persian = persian
                        item.notes = notes
                        item.meaningSource = "You"
                        modelContext.insert(item)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(german.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Category Manager

struct CategoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomCategory.name) private var customCategories: [CustomCategory]
    @State private var newCategoryName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Custom Categories") {
                    if customCategories.isEmpty {
                        Text("No custom categories")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(customCategories) { cat in
                            HStack {
                                Text(cat.name)
                                Spacer()
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(cat)
                                    try? modelContext.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section("Add Custom Category") {
                    HStack {
                        TextField("Name", text: $newCategoryName)
                        Button("Add") {
                            let cat = CustomCategory(name: newCategoryName)
                            modelContext.insert(cat)
                            try? modelContext.save()
                            newCategoryName = ""
                        }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Built-in Categories") {
                    ForEach(VocabCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Manage Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
