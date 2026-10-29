import SwiftUI
import Foundation

// MARK: - Fleet operations data

struct DutyOfficerRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var department: String
    var rarity: String
    var specialization: String
    var assignment: String
    var notes: String
}

struct CooldownRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: String
    var readyAt: Date
    var notes: String
}

struct InventoryRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: String
    var quantity: Int
    var targetQuantity: Int
    var notes: String
}

@MainActor
final class FleetOperationsStore: ObservableObject {
    static let shared = FleetOperationsStore()

    @Published private(set) var officers: [DutyOfficerRecord] = []
    @Published private(set) var cooldowns: [CooldownRecord] = []
    @Published private(set) var inventory: [InventoryRecord] = []

    private let defaults = UserDefaults.standard

    private init() {
        officers = load([DutyOfficerRecord].self, key: "fleet.officers") ?? []
        cooldowns = load([CooldownRecord].self, key: "fleet.cooldowns") ?? []
        inventory = load([InventoryRecord].self, key: "fleet.inventory") ?? []
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    func saveOfficer(_ item: DutyOfficerRecord) {
        if let index = officers.firstIndex(where: { $0.id == item.id }) { officers[index] = item }
        else { officers.insert(item, at: 0) }
        save(officers, key: "fleet.officers")
    }

    func deleteOfficer(_ item: DutyOfficerRecord) {
        officers.removeAll { $0.id == item.id }
        save(officers, key: "fleet.officers")
    }

    func saveCooldown(_ item: CooldownRecord) {
        if let index = cooldowns.firstIndex(where: { $0.id == item.id }) { cooldowns[index] = item }
        else { cooldowns.insert(item, at: 0) }
        cooldowns.sort { $0.readyAt < $1.readyAt }
        save(cooldowns, key: "fleet.cooldowns")
    }

    func deleteCooldown(_ item: CooldownRecord) {
        cooldowns.removeAll { $0.id == item.id }
        save(cooldowns, key: "fleet.cooldowns")
    }

    func saveInventory(_ item: InventoryRecord) {
        let normalized = InventoryRecord(id: item.id, name: item.name, category: item.category, quantity: max(0, item.quantity), targetQuantity: max(0, item.targetQuantity), notes: item.notes)
        if let index = inventory.firstIndex(where: { $0.id == item.id }) { inventory[index] = normalized }
        else { inventory.insert(normalized, at: 0) }
        inventory.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save(inventory, key: "fleet.inventory")
    }

    func adjustInventory(_ item: InventoryRecord, by amount: Int) {
        var updated = item
        updated.quantity = max(0, updated.quantity + amount)
        saveInventory(updated)
    }

    func deleteInventory(_ item: InventoryRecord) {
        inventory.removeAll { $0.id == item.id }
        save(inventory, key: "fleet.inventory")
    }
}

// MARK: - Duty officer roster

struct DutyOfficerRosterView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = FleetOperationsStore.shared
    @State private var editing: DutyOfficerRecord?
    @State private var showingEditor = false
    @State private var search = ""

    private var filtered: [DutyOfficerRecord] {
        store.officers.filter {
            search.isEmpty || [$0.name, $0.department, $0.specialization, $0.assignment].joined(separator: " ").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            Section {
                TextField("Search officers…", text: $search).listRowBackground(theme.surface)
                Button {
                    editing = nil
                    showingEditor = true
                } label: {
                    Label("Add duty officer", systemImage: "plus.circle.fill")
                }.listRowBackground(theme.surface)
            } header: { Text("Personnel file") }

            Section("Roster • \(store.officers.count)") {
                if filtered.isEmpty {
                    ContentUnavailableView("No duty officers", systemImage: "person.3", description: Text("Add officers to organize department, rarity, specialization, and assignment notes."))
                        .listRowBackground(theme.surface)
                }
                ForEach(filtered) { officer in
                    Button {
                        editing = officer
                        showingEditor = true
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(officer.name).font(.headline).foregroundStyle(.white)
                                Spacer()
                                Text(officer.rarity.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(theme.accent)
                            }
                            Text("\(officer.department) • \(officer.specialization)")
                                .font(.caption).foregroundStyle(theme.secondaryAccent)
                            if !officer.assignment.isEmpty {
                                Text("Assignment: \(officer.assignment)")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.65))
                            }
                            if !officer.notes.isEmpty {
                                Text(officer.notes).font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                            }
                        }
                    }
                    .listRowBackground(theme.surface)
                    .swipeActions {
                        Button(role: .destructive) { store.deleteOfficer(officer) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .sheet(isPresented: $showingEditor) {
            DutyOfficerEditorView(officer: editing ?? DutyOfficerRecord(name: "", department: "Engineering", rarity: "Common", specialization: "", assignment: "", notes: ""))
        }
    }
}

private struct DutyOfficerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = FleetOperationsStore.shared
    @State var officer: DutyOfficerRecord

    var body: some View {
        NavigationStack {
            Form {
                Section("Officer") {
                    TextField("Name", text: $officer.name)
                    Picker("Department", selection: $officer.department) {
                        ForEach(["Engineering", "Science", "Tactical", "Civilian", "Security"], id: \.self) { Text($0) }
                    }
                    Picker("Rarity", selection: $officer.rarity) {
                        ForEach(["Common", "Uncommon", "Rare", "Very Rare", "Ultra Rare", "Epic"], id: \.self) { Text($0) }
                    }
                    TextField("Specialization / active duty bonus", text: $officer.specialization)
                    TextField("Assignment / station", text: $officer.assignment)
                }
                Section("Notes") { TextEditor(text: $officer.notes).frame(minHeight: 90) }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Duty Officer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveOfficer(officer); dismiss() }
                        .disabled(officer.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }
}

// MARK: - Cooldown and event reminders

struct CooldownPlannerView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = FleetOperationsStore.shared
    @State private var editing: CooldownRecord?
    @State private var showingEditor = false
    @State private var now = Date()

    private var sorted: [CooldownRecord] { store.cooldowns.sorted { $0.readyAt < $1.readyAt } }

    var body: some View {
        List {
            Section {
                Button {
                    editing = nil
                    showingEditor = true
                } label: {
                    Label("Add cooldown or event", systemImage: "plus.circle.fill")
                }.listRowBackground(theme.surface)
                Text("Create your own timers for reputation projects, crafting, events, or any other game activity. Times are local to this device.")
                    .font(.caption).foregroundStyle(.secondary).listRowBackground(theme.surface)
            }
            Section("Upcoming • \(sorted.count)") {
                if sorted.isEmpty {
                    ContentUnavailableView("No timers", systemImage: "timer", description: Text("Add a custom ready time to start tracking cooldowns and events."))
                        .listRowBackground(theme.surface)
                }
                ForEach(sorted) { item in
                    Button {
                        editing = item
                        showingEditor = true
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.name).font(.headline).foregroundStyle(.white)
                                Spacer()
                                Text(item.readyAt <= now ? "READY" : "UPCOMING")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(item.readyAt <= now ? .green : theme.accent)
                            }
                            Text(item.category).font(.caption).foregroundStyle(theme.secondaryAccent)
                            Text(item.readyAt, style: .date).font(.caption2).foregroundStyle(.white.opacity(0.7))
                            Text(item.readyAt, style: .time).font(.caption2).foregroundStyle(.white.opacity(0.7))
                            Text(item.readyAt <= now ? "Ready to claim or start" : item.readyAt, style: item.readyAt <= now ? .relative : .relative)
                                .font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                            if !item.notes.isEmpty {
                                Text(item.notes).font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                            }
                        }
                    }
                    .listRowBackground(theme.surface)
                    .swipeActions {
                        Button(role: .destructive) { store.deleteCooldown(item) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in now = date }
        .sheet(isPresented: $showingEditor) {
            CooldownEditorView(item: editing ?? CooldownRecord(name: "", category: "Reputation", readyAt: Date().addingTimeInterval(3600), notes: ""))
        }
    }
}

private struct CooldownEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = FleetOperationsStore.shared
    @State var item: CooldownRecord

    var body: some View {
        NavigationStack {
            Form {
                Section("Timer details") {
                    TextField("Name", text: $item.name)
                    Picker("Category", selection: $item.category) {
                        ForEach(["Reputation", "Crafting", "Event", "Mission", "Daily", "Weekly", "Other"], id: \.self) { Text($0) }
                    }
                    DatePicker("Ready at", selection: $item.readyAt, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Notes") { TextEditor(text: $item.notes).frame(minHeight: 80) }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Cooldown Timer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveCooldown(item); dismiss() }
                        .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }
}

// MARK: - Inventory and resource checklist

struct InventoryChecklistView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = FleetOperationsStore.shared
    @State private var editing: InventoryRecord?
    @State private var showingEditor = false
    @State private var filter = "All"

    private var categories: [String] { ["All", "Upgrade", "Currency", "Crafting", "Event", "Other"] }
    private var filtered: [InventoryRecord] {
        store.inventory.filter { filter == "All" || $0.category == filter }
    }

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $filter) {
                    ForEach(categories, id: \.self) { Text($0) }
                }.listRowBackground(theme.surface)
                Button {
                    editing = nil
                    showingEditor = true
                } label: {
                    Label("Add inventory item", systemImage: "plus.circle.fill")
                }.listRowBackground(theme.surface)
            } header: { Text("Personal inventory") }

            Section("Tracked items • \(filtered.count)") {
                if filtered.isEmpty {
                    ContentUnavailableView("Inventory is empty", systemImage: "shippingbox", description: Text("Track currencies, crafting materials, upgrade tokens, and event resources manually."))
                        .listRowBackground(theme.surface)
                }
                ForEach(filtered) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Button {
                                editing = item
                                showingEditor = true
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).font(.headline).foregroundStyle(.white)
                                    Text(item.category).font(.caption).foregroundStyle(theme.secondaryAccent)
                                }
                            }.buttonStyle(.plain)
                            Spacer()
                            Text("\(item.quantity) / \(item.targetQuantity)")
                                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                                .foregroundStyle(.white)
                            Button { store.adjustInventory(item, by: 1) } label: {
                                Image(systemName: "plus.circle.fill").font(.title3)
                            }.buttonStyle(.plain)
                            Button { store.adjustInventory(item, by: -1) } label: {
                                Image(systemName: "minus.circle").font(.title3)
                            }.buttonStyle(.plain)
                        }
                        if item.targetQuantity > 0 {
                            ProgressView(value: min(Double(item.quantity), Double(item.targetQuantity)), total: Double(item.targetQuantity))
                                .tint(item.quantity >= item.targetQuantity ? .green : theme.accent)
                        }
                        if !item.notes.isEmpty {
                            Text(item.notes).font(.caption2).foregroundStyle(.white.opacity(0.52)).lineLimit(2)
                        }
                    }
                    .listRowBackground(theme.surface)
                    .swipeActions {
                        Button(role: .destructive) { store.deleteInventory(item) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .sheet(isPresented: $showingEditor) {
            InventoryEditorView(item: editing ?? InventoryRecord(name: "", category: "Other", quantity: 0, targetQuantity: 0, notes: ""))
        }
    }
}

private struct InventoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = FleetOperationsStore.shared
    @State var item: InventoryRecord

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $item.name)
                    Picker("Category", selection: $item.category) {
                        ForEach(["Upgrade", "Currency", "Crafting", "Event", "Other"], id: \.self) { Text($0) }
                    }
                    Stepper("Current quantity: \(item.quantity)", value: $item.quantity, in: 0...999999)
                    Stepper("Target quantity: \(item.targetQuantity)", value: $item.targetQuantity, in: 0...999999)
                }
                Section("Notes") { TextEditor(text: $item.notes).frame(minHeight: 80) }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Inventory Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveInventory(item); dismiss() }
                        .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }
}
