import SwiftUI
import Foundation
import UniformTypeIdentifiers

// MARK: - Structured ship loadouts

struct AdvancedShipLoadout: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var ship: String
    var captain: String
    var role: String
    var specialization: String
    var foreWeapons: [String] = Array(repeating: "", count: 5)
    var aftWeapons: [String] = Array(repeating: "", count: 5)
    var tacticalConsoles: [String] = Array(repeating: "", count: 5)
    var engineeringConsoles: [String] = Array(repeating: "", count: 5)
    var scienceConsoles: [String] = Array(repeating: "", count: 5)
    var universalConsoles: [String] = Array(repeating: "", count: 5)
    var bridgeOfficerSeats: [String] = Array(repeating: "", count: 6)
    var shipTraits: String = ""
    var personalTraits: String = ""
    var reputationTraits: String = ""
    var notes: String = ""
    var updatedAt = Date()
}

struct CraftingPlanRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: String
    var outputQuantity: Int
    var requiredMaterials: String
    var ownedMaterials: String
    var notes: String
}

struct EventCampaignRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var startDate: Date
    var endDate: Date
    var requiredDays: Int
    var completedDays: Int
    var reward: String
    var notes: String
}

struct WikiMirrorPage: Identifiable, Codable, Hashable {
    var id: String { title }
    let title: String
    let url: String
    let revisionID: Int?
    let text: String

    var safeURL: URL? {
        guard let value = URL(string: url),
              value.scheme == "https",
              value.host == "stowiki.net" || value.host == "www.stowiki.net" else { return nil }
        return value
    }
}

private struct WikiMirrorImportRow: Decodable {
    let title: String?
    let url: String?
    let revision_id: Int?
    let text: String?
}

@MainActor
final class AdvancedToolsStore: ObservableObject {
    static let shared = AdvancedToolsStore()

    @Published private(set) var loadouts: [AdvancedShipLoadout] = []
    @Published private(set) var craftingPlans: [CraftingPlanRecord] = []
    @Published private(set) var campaigns: [EventCampaignRecord] = []
    @Published private(set) var wikiPages: [WikiMirrorPage] = []
    @Published private(set) var catalogMessage: String?

    private let defaults = UserDefaults.standard
    private let catalogURL: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        catalogURL = documents.appendingPathComponent("stowiki-catalog.json")
        loadDefaults()
        loadCatalog()
    }

    private func loadDefaults() {
        if let data = defaults.data(forKey: "advanced.loadouts"),
           let value = try? JSONDecoder().decode([AdvancedShipLoadout].self, from: data) { loadouts = value }
        if let data = defaults.data(forKey: "advanced.crafting"),
           let value = try? JSONDecoder().decode([CraftingPlanRecord].self, from: data) { craftingPlans = value }
        if let data = defaults.data(forKey: "advanced.campaigns"),
           let value = try? JSONDecoder().decode([EventCampaignRecord].self, from: data) { campaigns = value }
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func loadCatalog() {
        guard let data = try? Data(contentsOf: catalogURL),
              let pages = try? JSONDecoder().decode([WikiMirrorPage].self, from: data) else { return }
        wikiPages = pages
    }

    func saveLoadout(_ item: AdvancedShipLoadout) {
        var value = item
        value.updatedAt = Date()
        if let index = loadouts.firstIndex(where: { $0.id == value.id }) { loadouts[index] = value }
        else { loadouts.insert(value, at: 0) }
        persist(loadouts, key: "advanced.loadouts")
    }

    func importLoadouts(_ imported: [AdvancedShipLoadout]) {
        for item in imported {
            if let index = loadouts.firstIndex(where: { $0.id == item.id }) { loadouts[index] = item }
            else { loadouts.insert(item, at: 0) }
        }
        persist(loadouts, key: "advanced.loadouts")
    }

    func deleteLoadout(_ item: AdvancedShipLoadout) {
        loadouts.removeAll { $0.id == item.id }
        persist(loadouts, key: "advanced.loadouts")
    }

    func saveCrafting(_ item: CraftingPlanRecord) {
        let value = CraftingPlanRecord(id: item.id, name: item.name, category: item.category, outputQuantity: max(1, item.outputQuantity), requiredMaterials: item.requiredMaterials, ownedMaterials: item.ownedMaterials, notes: item.notes)
        if let index = craftingPlans.firstIndex(where: { $0.id == value.id }) { craftingPlans[index] = value }
        else { craftingPlans.insert(value, at: 0) }
        persist(craftingPlans, key: "advanced.crafting")
    }

    func deleteCrafting(_ item: CraftingPlanRecord) {
        craftingPlans.removeAll { $0.id == item.id }
        persist(craftingPlans, key: "advanced.crafting")
    }

    func saveCampaign(_ item: EventCampaignRecord) {
        let value = EventCampaignRecord(id: item.id, name: item.name, startDate: item.startDate, endDate: item.endDate, requiredDays: max(0, item.requiredDays), completedDays: min(max(0, item.completedDays), max(0, item.requiredDays)), reward: item.reward, notes: item.notes)
        if let index = campaigns.firstIndex(where: { $0.id == value.id }) { campaigns[index] = value }
        else { campaigns.insert(value, at: 0) }
        persist(campaigns, key: "advanced.campaigns")
    }

    func deleteCampaign(_ item: EventCampaignRecord) {
        campaigns.removeAll { $0.id == item.id }
        persist(campaigns, key: "advanced.campaigns")
    }

    func importWikiMirror(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= 250 * 1024 * 1024 else {
            throw NSError(domain: "STOWikiCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a non-empty pages.jsonl file no larger than 250 MB."])
        }

        let raw = try Data(contentsOf: url)
        guard let source = String(data: raw, encoding: .utf8) else {
            throw NSError(domain: "STOWikiCatalog", code: 2, userInfo: [NSLocalizedDescriptionKey: "The selected mirror is not valid UTF-8 text."])
        }

        let decoder = JSONDecoder()
        var byTitle: [String: WikiMirrorPage] = [:]
        var rejected = 0
        for line in source.split(whereSeparator: \.isNewline).prefix(25000) {
            guard let data = String(line).data(using: .utf8),
                  let row = try? decoder.decode(WikiMirrorImportRow.self, from: data),
                  let title = row.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  let rawURL = row.url,
                  let parsed = URL(string: rawURL),
                  parsed.scheme == "https",
                  parsed.host == "stowiki.net" || parsed.host == "www.stowiki.net" else {
                rejected += 1
                continue
            }
            let text = String((row.text ?? "").prefix(4000))
            byTitle[title] = WikiMirrorPage(title: title, url: rawURL, revisionID: row.revision_id, text: text)
        }

        let imported = byTitle.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        guard !imported.isEmpty else {
            throw NSError(domain: "STOWikiCatalog", code: 3, userInfo: [NSLocalizedDescriptionKey: "No valid STO Wiki pages were found in that file."])
        }
        let encoded = try JSONEncoder().encode(imported)
        try encoded.write(to: catalogURL, options: .atomic)
        wikiPages = imported
        catalogMessage = "Imported \(imported.count.formatted()) pages. \(rejected) rows were skipped."
    }
}

// MARK: - Loadout builder and comparison

struct AdvancedLoadoutView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = AdvancedToolsStore.shared
    @State private var editing: AdvancedShipLoadout?
    @State private var showingEditor = false
    @State private var showingComparison = false
    @State private var showingImporter = false
    @State private var archiveDocument: ShipLoadoutArchiveDocument?
    @State private var exporting = false
    @State private var archiveMessage: String?

    var body: some View {
        List {
            Section {
                Button { editing = nil; showingEditor = true } label: { Label("Create detailed loadout", systemImage: "plus.circle.fill") }
                Button { showingComparison = true } label: { Label("Compare two loadouts", systemImage: "arrow.left.arrow.right") }
                    .disabled(store.loadouts.count < 2)
                Button { archiveDocument = ShipLoadoutArchiveDocument(loadouts: store.loadouts); exporting = true } label: { Label("Export loadouts", systemImage: "square.and.arrow.up") }
                    .disabled(store.loadouts.isEmpty)
                Button { showingImporter = true } label: { Label("Import loadouts", systemImage: "square.and.arrow.down") }
                if let archiveMessage { Text(archiveMessage).font(.caption).foregroundStyle(.secondary) }
            }.listRowBackground(theme.surface)
            Section("Saved loadouts • \(store.loadouts.count)") {
                if store.loadouts.isEmpty {
                    ContentUnavailableView("No detailed loadouts", systemImage: "ship", description: Text("Build a structured configuration with weapon, console, and bridge officer slots."))
                        .listRowBackground(theme.surface)
                }
                ForEach(store.loadouts) { item in
                    Button { editing = item; showingEditor = true } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.headline).foregroundStyle(.white)
                            Text("\(item.ship) • \(item.role) • \(item.specialization)").font(.caption).foregroundStyle(theme.secondaryAccent)
                            Text("Updated \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.white.opacity(0.5))
                        }
                    }.listRowBackground(theme.surface)
                    .swipeActions { Button(role: .destructive) { store.deleteLoadout(item) } label: { Label("Delete", systemImage: "trash") } }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .sheet(isPresented: $showingEditor) {
            AdvancedLoadoutEditor(item: editing ?? AdvancedShipLoadout(name: "", ship: "", captain: "", role: "Damage", specialization: "None"))
        }
        .sheet(isPresented: $showingComparison) { LoadoutComparisonView() }
        .fileExporter(isPresented: $exporting, document: archiveDocument, contentType: .json, defaultFilename: "STOWiki-Loadouts") { result in
            switch result { case .success(let url): archiveMessage = "Exported loadouts to \(url.lastPathComponent)."; case .failure(let error): archiveMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let archive = try JSONDecoder().decode(ShipLoadoutArchive.self, from: Data(contentsOf: url))
                guard archive.formatVersion == 1 else { throw NSError(domain: "STOWikiLoadoutArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported archive version."]) }
                store.importLoadouts(archive.loadouts)
                archiveMessage = "Imported \\(archive.loadouts.count) loadouts."
            } catch { archiveMessage = error.localizedDescription }
        }
    }
}

private struct AdvancedLoadoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = AdvancedToolsStore.shared
    @State var item: AdvancedShipLoadout

    var body: some View {
        NavigationStack {
            Form {
                Section("Ship and captain") {
                    TextField("Loadout name", text: $item.name)
                    TextField("Ship", text: $item.ship)
                    TextField("Captain", text: $item.captain)
                    Picker("Role", selection: $item.role) {
                        ForEach(["Damage", "Tank", "Science / Exotic", "Support", "Control", "Healing", "Hybrid"], id: \.self) { Text($0) }
                    }
                    Picker("Primary specialization", selection: $item.specialization) {
                        ForEach(["None", "Command", "Intel", "Miracle Worker", "Pilot", "Temporal Operative"], id: \.self) { Text($0) }
                    }
                }
                slotSection("Fore weapons", values: $item.foreWeapons)
                slotSection("Aft weapons", values: $item.aftWeapons)
                slotSection("Tactical consoles", values: $item.tacticalConsoles)
                slotSection("Engineering consoles", values: $item.engineeringConsoles)
                slotSection("Science consoles", values: $item.scienceConsoles)
                slotSection("Universal consoles", values: $item.universalConsoles)
                slotSection("Bridge officer seating", values: $item.bridgeOfficerSeats)
                Section("Traits") {
                    TextField("Starship traits", text: $item.shipTraits, axis: .vertical).lineLimit(2...5)
                    TextField("Personal traits", text: $item.personalTraits, axis: .vertical).lineLimit(2...5)
                    TextField("Reputation / other traits", text: $item.reputationTraits, axis: .vertical).lineLimit(2...5)
                }
                Section("Notes") { TextEditor(text: $item.notes).frame(minHeight: 100) }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Loadout Builder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveLoadout(item); dismiss() }
                        .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty || item.ship.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }

    private func slotSection(_ title: String, values: Binding<[String]>) -> some View {
        Section(title) {
            ForEach(values.wrappedValue.indices, id: \.self) { index in
                TextField("Slot \(index + 1)", text: Binding(
                    get: { index < values.wrappedValue.count ? values.wrappedValue[index] : "" },
                    set: { newValue in
                        guard index < values.wrappedValue.count else { return }
                        values.wrappedValue[index] = newValue
                    }
                ))
            }
        }
    }
}

private struct LoadoutComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = AdvancedToolsStore.shared
    @State private var leftID: UUID?
    @State private var rightID: UUID?

    private var left: AdvancedShipLoadout? { store.loadouts.first { $0.id == leftID } }
    private var right: AdvancedShipLoadout? { store.loadouts.first { $0.id == rightID } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Choose configurations") {
                    Picker("Loadout A", selection: $leftID) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(store.loadouts) { item in Text(item.name).tag(Optional(item.id)) }
                    }
                    Picker("Loadout B", selection: $rightID) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(store.loadouts) { item in Text(item.name).tag(Optional(item.id)) }
                    }
                }
                if let left, let right {
                    Section("At a glance") {
                        compareRow("Ship", left.ship, right.ship)
                        compareRow("Role", left.role, right.role)
                        compareRow("Specialization", left.specialization, right.specialization)
                        compareRow("Captain", left.captain, right.captain)
                    }
                    Section("Weapons and consoles") {
                        compareRow("Fore weapons", filled(left.foreWeapons), filled(right.foreWeapons))
                        compareRow("Aft weapons", filled(left.aftWeapons), filled(right.aftWeapons))
                        compareRow("Tactical", filled(left.tacticalConsoles), filled(right.tacticalConsoles))
                        compareRow("Engineering", filled(left.engineeringConsoles), filled(right.engineeringConsoles))
                        compareRow("Science", filled(left.scienceConsoles), filled(right.scienceConsoles))
                        compareRow("Universal", filled(left.universalConsoles), filled(right.universalConsoles))
                        compareRow("Bridge officers", filled(left.bridgeOfficerSeats), filled(right.bridgeOfficerSeats))
                    }
                    Section("Traits") {
                        compareRow("Starship", left.shipTraits, right.shipTraits)
                        compareRow("Personal", left.personalTraits, right.personalTraits)
                        compareRow("Reputation", left.reputationTraits, right.reputationTraits)
                    }
                } else {
                    Text("Select two saved loadouts to compare their slots and traits.")
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Loadout Comparison")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(theme.accent).preferredColorScheme(.dark)
        .onAppear {
            if leftID == nil { leftID = store.loadouts.first?.id }
            if rightID == nil { rightID = store.loadouts.dropFirst().first?.id }
        }
    }

    private func filled(_ values: [String]) -> String {
        let entries = values.enumerated().compactMap { index, value in
            value.isEmpty ? nil : "\(index + 1). \(value)"
        }
        return entries.isEmpty ? "—" : entries.joined(separator: "\n")
    }

    private func compareRow(_ title: String, _ a: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(theme.secondaryAccent)
            HStack(alignment: .top, spacing: 12) {
                Text(a.isEmpty ? "—" : a).frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                Text(b.isEmpty ? "—" : b).frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption).foregroundStyle(.white)
        }
    }
}

// MARK: - Crafting planner

struct CraftingPlannerView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = AdvancedToolsStore.shared
    @State private var editing: CraftingPlanRecord?
    @State private var showingEditor = false

    var body: some View {
        List {
            Section {
                Button { editing = nil; showingEditor = true } label: { Label("Add crafting plan", systemImage: "plus.circle.fill") }
                Text("Enter recipe requirements and what you own. Material shortages are calculated from your entries; recipes are not fetched live.")
                    .font(.caption).foregroundStyle(.secondary)
            }.listRowBackground(theme.surface)
            Section("Recipes • \(store.craftingPlans.count)") {
                if store.craftingPlans.isEmpty {
                    ContentUnavailableView("No crafting plans", systemImage: "hammer", description: Text("Save recipes and material requirements to plan your next upgrade or project."))
                        .listRowBackground(theme.surface)
                }
                ForEach(store.craftingPlans) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Button { editing = item; showingEditor = true } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.headline).foregroundStyle(.white)
                                Text("\(item.category) • Output: \(item.outputQuantity)").font(.caption).foregroundStyle(theme.secondaryAccent)
                            }
                        }.buttonStyle(.plain)
                        ForEach(materialShortages(item), id: \.name) { shortage in
                            HStack {
                                Text(shortage.name).font(.caption)
                                Spacer()
                                Text("Need \(shortage.missing)").font(.caption.monospacedDigit()).foregroundStyle(.orange)
                            }
                        }
                        if materialShortages(item).isEmpty {
                            Label("No recorded material shortages", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
                        }
                    }.listRowBackground(theme.surface)
                    .swipeActions { Button(role: .destructive) { store.deleteCrafting(item) } label: { Label("Delete", systemImage: "trash") } }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .sheet(isPresented: $showingEditor) {
            CraftingPlanEditor(item: editing ?? CraftingPlanRecord(name: "", category: "Upgrade", outputQuantity: 1, requiredMaterials: "", ownedMaterials: "", notes: ""))
        }
    }

    private func materialShortages(_ item: CraftingPlanRecord) -> [(name: String, missing: Int)] {
        func parse(_ source: String) -> [String: Int] {
            var values: [String: Int] = [:]
            for line in source.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, let quantity = Int(parts[1]), quantity >= 0 else { continue }
                values[parts[0].lowercased()] = quantity
            }
            return values
        }
        let required = parse(item.requiredMaterials)
        let owned = parse(item.ownedMaterials)
        return required.keys.sorted().compactMap { key in
            let missing = max(0, (required[key] ?? 0) - (owned[key] ?? 0))
            guard missing > 0 else { return nil }
            return (key.capitalized, missing)
        }
    }
}

private struct CraftingPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = AdvancedToolsStore.shared
    @State var item: CraftingPlanRecord

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Recipe / item name", text: $item.name)
                    Picker("Category", selection: $item.category) {
                        ForEach(["Upgrade", "Crafting", "Re-engineering", "Project", "Other"], id: \.self) { Text($0) }
                    }
                    Stepper("Output quantity: \(item.outputQuantity)", value: $item.outputQuantity, in: 1...999999)
                }
                Section("Required materials") {
                    Text("One material per line, formatted as Material: quantity").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $item.requiredMaterials).frame(minHeight: 110)
                }
                Section("Materials owned") {
                    Text("Use the same format to calculate shortages").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $item.ownedMaterials).frame(minHeight: 110)
                }
                Section("Notes") { TextEditor(text: $item.notes).frame(minHeight: 80) }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Crafting Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveCrafting(item); dismiss() }
                        .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }
}

// MARK: - Event campaign planner

struct EventCampaignPlannerView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = AdvancedToolsStore.shared
    @State private var editing: EventCampaignRecord?
    @State private var showingEditor = false
    @State private var reminderMessage: String?

    var body: some View {
        List {
            Section {
                Button { editing = nil; showingEditor = true } label: { Label("Add event campaign", systemImage: "plus.circle.fill") }
                Text("Track participation days and reward goals for events or campaigns. Dates and requirements are user-entered, not live event schedules.")
                    .font(.caption).foregroundStyle(.secondary)
            }.listRowBackground(theme.surface)
            Section("Campaigns • \(store.campaigns.count)") {
                if store.campaigns.isEmpty {
                    ContentUnavailableView("No campaigns tracked", systemImage: "calendar", description: Text("Add an event, campaign, or limited-time reward goal."))
                        .listRowBackground(theme.surface)
                }
                ForEach(store.campaigns) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(item.name).font(.headline).foregroundStyle(.white)
                            Spacer()
                            Text("\(item.completedDays) / \(item.requiredDays) days").font(.caption.monospacedDigit()).foregroundStyle(theme.accent)
                        }
                        ProgressView(value: Double(item.completedDays), total: Double(max(1, item.requiredDays)))
                            .tint(item.completedDays >= item.requiredDays ? .green : theme.accent)
                        Text("\(item.startDate.formatted(date: .abbreviated, time: .omitted)) – \(item.endDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2).foregroundStyle(.white.opacity(0.6))
                        if !item.reward.isEmpty { Label(item.reward, systemImage: "gift").font(.caption).foregroundStyle(theme.secondaryAccent) }
                        HStack {
                            Button {
                                Task {
                                    do { try await CampaignReminderService.shared.schedule(for: item); reminderMessage = "Campaign reminders scheduled." }
                                    catch { reminderMessage = error.localizedDescription }
                                }
                            } label: { Label("Remind me", systemImage: "bell.badge") }
                            Button { var updated = item; updated.completedDays = max(0, updated.completedDays - 1); store.saveCampaign(updated) } label: { Label("− Day", systemImage: "minus") }
                            Button { var updated = item; updated.completedDays = min(updated.requiredDays, updated.completedDays + 1); store.saveCampaign(updated) } label: { Label("+ Day", systemImage: "plus") }
                        }.font(.caption)
                    }.listRowBackground(theme.surface)
                    .swipeActions {
                        Button { editing = item; showingEditor = true } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                        Button(role: .destructive) { store.deleteCampaign(item) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .alert("Campaign reminders", isPresented: Binding(get: { reminderMessage != nil }, set: { if !$0 { reminderMessage = nil } })) { Button("OK") { reminderMessage = nil } } message: { Text(reminderMessage ?? "") }
        .sheet(isPresented: $showingEditor) {
            EventCampaignEditor(item: editing ?? EventCampaignRecord(name: "", startDate: Date(), endDate: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date(), requiredDays: 20, completedDays: 0, reward: "", notes: ""))
        }
    }
}

private struct EventCampaignEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = AdvancedToolsStore.shared
    @State var item: EventCampaignRecord

    var body: some View {
        NavigationStack {
            Form {
                Section("Campaign") {
                    TextField("Event / campaign name", text: $item.name)
                    DatePicker("Starts", selection: $item.startDate, displayedComponents: .date)
                    DatePicker("Ends", selection: $item.endDate, in: item.startDate..., displayedComponents: .date)
                    Stepper("Required participation days: \(item.requiredDays)", value: $item.requiredDays, in: 0...999)
                    Stepper("Completed days: \(item.completedDays)", value: $item.completedDays, in: 0...999)
                    TextField("Reward goal", text: $item.reward)
                }
                Section("Notes") { TextEditor(text: $item.notes).frame(minHeight: 80) }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Event Campaign")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveCampaign(item); dismiss() }
                        .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }
}

// MARK: - Importable, searchable wiki mirror catalog

struct WikiMirrorCatalogView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = AdvancedToolsStore.shared
    @State private var search = ""
    @State private var showingImporter = false
    @State private var importError: String?

    private var results: [WikiMirrorPage] {
        guard !search.isEmpty else { return Array(store.wikiPages.prefix(150)) }
        return Array(store.wikiPages.lazy.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search)
        }.prefix(150))
    }

    var body: some View {
        List {
            Section {
                Button { showingImporter = true } label: { Label("Import wiki mirror pages.jsonl", systemImage: "square.and.arrow.down") }
                Text(store.wikiPages.isEmpty
                     ? "Import pages.jsonl from a GitHub Actions stowiki-mirror artifact to create an on-device searchable catalog."
                     : "\(store.wikiPages.count.formatted()) pages available offline. Importing another mirror replaces this catalog.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = store.catalogMessage { Text(message).font(.caption).foregroundStyle(.green) }
                if let importError { Text(importError).font(.caption).foregroundStyle(.red) }
            }.listRowBackground(theme.surface)
            Section("Wiki pages • \(results.count) shown") {
                if results.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No wiki catalog" : "No matching pages", systemImage: "books.vertical", description: Text(search.isEmpty ? "Import the pages.jsonl mirror file to get started." : "Try another title or keyword."))
                        .listRowBackground(theme.surface)
                }
                ForEach(results) { page in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(page.title).font(.headline).foregroundStyle(.white)
                            Spacer()
                            if let url = page.safeURL { Link("Wiki", destination: url).font(.caption) }
                        }
                        Text(page.text.isEmpty ? "No text extract in this mirror record." : page.text)
                            .font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(4)
                        if let revision = page.revisionID {
                            Text("Revision \(revision)").font(.system(size: 9, design: .monospaced)).foregroundStyle(theme.secondaryAccent)
                        }
                    }.listRowBackground(theme.surface)
                }
            }
        }
        .searchable(text: $search, prompt: "Search imported wiki pages")
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.plainText, .json, UTType(filenameExtension: "jsonl") ?? .plainText], allowsMultipleSelection: false) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                try store.importWikiMirror(from: url)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}
