import SwiftUI
import Foundation
import Combine

struct ReputationProgressRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var reputation: String
    var tier: Int
    var marks: Int
    var dailyProject: String
    var notes: String
}

struct FleetProjectRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var holding: String
    var project: String
    var resource: String
    var current: Int
    var target: Int
    var deadline: Date?
    var notes: String
}

struct ExchangePriceRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var item: String
    var category: String
    var buyPrice: Int
    var sellPrice: Int
    var quantity: Int
    var notes: String
    var updatedAt = Date()

    var spread: Int { sellPrice - buyPrice }
    var totalBuyCost: Int { buyPrice.multipliedReportingOverflow(by: quantity).overflow ? Int.max : buyPrice * quantity }
    var totalSellValue: Int { sellPrice.multipliedReportingOverflow(by: quantity).overflow ? Int.max : sellPrice * quantity }
}

@MainActor
final class ProgressionEconomyStore: ObservableObject {
    static let shared = ProgressionEconomyStore()

    @Published private(set) var reputations: [ReputationProgressRecord] = []
    @Published private(set) var fleetProjects: [FleetProjectRecord] = []
    @Published private(set) var exchangeItems: [ExchangePriceRecord] = []

    private init() {
        reputations = load([ReputationProgressRecord].self, key: "progression.reputations") ?? []
        fleetProjects = load([FleetProjectRecord].self, key: "progression.fleetProjects") ?? []
        exchangeItems = load([ExchangePriceRecord].self, key: "progression.exchangeItems") ?? []
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func saveReputation(_ item: ReputationProgressRecord) {
        let value = ReputationProgressRecord(id: item.id, reputation: item.reputation, tier: min(6, max(0, item.tier)), marks: max(0, item.marks), dailyProject: item.dailyProject, notes: item.notes)
        if let i = reputations.firstIndex(where: { $0.id == value.id }) { reputations[i] = value }
        else { reputations.append(value) }
        reputations.sort { $0.reputation.localizedCaseInsensitiveCompare($1.reputation) == .orderedAscending }
        save(reputations, key: "progression.reputations")
    }

    func deleteReputation(_ item: ReputationProgressRecord) {
        reputations.removeAll { $0.id == item.id }
        save(reputations, key: "progression.reputations")
    }

    func saveFleetProject(_ item: FleetProjectRecord) {
        let value = FleetProjectRecord(id: item.id, holding: item.holding, project: item.project, resource: item.resource, current: max(0, item.current), target: max(0, item.target), deadline: item.deadline, notes: item.notes)
        if let i = fleetProjects.firstIndex(where: { $0.id == value.id }) { fleetProjects[i] = value }
        else { fleetProjects.insert(value, at: 0) }
        save(fleetProjects, key: "progression.fleetProjects")
    }

    func deleteFleetProject(_ item: FleetProjectRecord) {
        fleetProjects.removeAll { $0.id == item.id }
        save(fleetProjects, key: "progression.fleetProjects")
    }

    func saveExchangeItem(_ item: ExchangePriceRecord) {
        let value = ExchangePriceRecord(id: item.id, item: item.item, category: item.category, buyPrice: max(0, item.buyPrice), sellPrice: max(0, item.sellPrice), quantity: max(0, item.quantity), notes: item.notes, updatedAt: Date())
        if let i = exchangeItems.firstIndex(where: { $0.id == value.id }) { exchangeItems[i] = value }
        else { exchangeItems.insert(value, at: 0) }
        save(exchangeItems, key: "progression.exchangeItems")
    }

    func deleteExchangeItem(_ item: ExchangePriceRecord) {
        exchangeItems.removeAll { $0.id == item.id }
        save(exchangeItems, key: "progression.exchangeItems")
    }
}

// MARK: - Reputation progression

struct ReputationManagerView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = ProgressionEconomyStore.shared
    @State private var editing: ReputationProgressRecord?
    @State private var showingEditor = false

    var body: some View {
        List {
            Section {
                Button { editing = nil; showingEditor = true } label: {
                    Label("Track reputation", systemImage: "plus.circle.fill")
                }.listRowBackground(theme.surface)
                Text("Record your own tier, marks on hand, and active daily project for each reputation. This tracker does not read game account data.")
                    .font(.caption).foregroundStyle(.secondary).listRowBackground(theme.surface)
            }
            Section("Reputation systems • \(store.reputations.count)") {
                if store.reputations.isEmpty {
                    ContentUnavailableView("No reputations tracked", systemImage: "medal", description: Text("Add a reputation to track your tier and marks."))
                        .listRowBackground(theme.surface)
                }
                ForEach(store.reputations) { item in
                    Button { editing = item; showingEditor = true } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.reputation).font(.headline).foregroundStyle(.white)
                                Spacer()
                                Text("TIER \(item.tier)").font(.system(.caption, design: .monospaced, weight: .bold)).foregroundStyle(theme.accent)
                            }
                            Text("\(item.marks.formatted()) marks").font(.caption).foregroundStyle(theme.secondaryAccent)
                            if !item.dailyProject.isEmpty {
                                Label(item.dailyProject, systemImage: "clock").font(.caption2).foregroundStyle(.white.opacity(0.7))
                            }
                            if !item.notes.isEmpty { Text(item.notes).font(.caption2).foregroundStyle(.white.opacity(0.55)).lineLimit(2) }
                        }
                    }.listRowBackground(theme.surface)
                    .swipeActions { Button(role: .destructive) { store.deleteReputation(item) } label: { Label("Delete", systemImage: "trash") } }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .sheet(isPresented: $showingEditor) {
            ReputationEditorView(item: editing ?? ReputationProgressRecord(reputation: "", tier: 0, marks: 0, dailyProject: "", notes: ""))
        }
    }
}

private struct ReputationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = ProgressionEconomyStore.shared
    @State var item: ReputationProgressRecord

    var body: some View {
        NavigationStack {
            Form {
                Section("Reputation") {
                    TextField("Reputation name", text: $item.reputation)
                    Stepper("Tier: \(item.tier)", value: $item.tier, in: 0...6)
                    Stepper("Marks: \(item.marks)", value: $item.marks, in: 0...999999)
                    TextField("Active daily project", text: $item.dailyProject)
                }
                Section("Notes") { TextEditor(text: $item.notes).frame(minHeight: 90) }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Reputation Progress")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveReputation(item); dismiss() }
                        .disabled(item.reputation.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }
}

// MARK: - Fleet holdings and projects

struct FleetProjectBoardView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = ProgressionEconomyStore.shared
    @State private var editing: FleetProjectRecord?
    @State private var showingEditor = false

    var body: some View {
        List {
            Section {
                Button { editing = nil; showingEditor = true } label: {
                    Label("Add fleet project", systemImage: "plus.circle.fill")
                }.listRowBackground(theme.surface)
                Text("Track fleet holdings, project contributions, and personal resource targets. Values are manually maintained.")
                    .font(.caption).foregroundStyle(.secondary).listRowBackground(theme.surface)
            }
            Section("Fleet projects • \(store.fleetProjects.count)") {
                if store.fleetProjects.isEmpty {
                    ContentUnavailableView("No fleet projects", systemImage: "building.2", description: Text("Add a holding project and track your contribution toward its target."))
                        .listRowBackground(theme.surface)
                }
                ForEach(store.fleetProjects) { item in
                    Button { editing = item; showingEditor = true } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.project).font(.headline).foregroundStyle(.white)
                                Spacer()
                                Text("\(item.current) / \(item.target)").font(.system(.caption, design: .monospaced, weight: .semibold)).foregroundStyle(theme.accent)
                            }
                            Text("\(item.holding) • \(item.resource)").font(.caption).foregroundStyle(theme.secondaryAccent)
                            if item.target > 0 {
                                ProgressView(value: min(Double(item.current), Double(item.target)), total: Double(item.target))
                                    .tint(item.current >= item.target ? .green : theme.accent)
                            }
                            if let deadline = item.deadline {
                                Text("Target date: \(deadline.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.white.opacity(0.65))
                            }
                            if !item.notes.isEmpty { Text(item.notes).font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(2) }
                        }
                    }.listRowBackground(theme.surface)
                    .swipeActions { Button(role: .destructive) { store.deleteFleetProject(item) } label: { Label("Delete", systemImage: "trash") } }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .sheet(isPresented: $showingEditor) {
            FleetProjectEditorView(item: editing ?? FleetProjectRecord(holding: "Starbase", project: "", resource: "Dilithium", current: 0, target: 0, deadline: nil, notes: ""))
        }
    }
}

private struct FleetProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = ProgressionEconomyStore.shared
    @State var item: FleetProjectRecord
    @State private var hasDeadline = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    Picker("Holding", selection: $item.holding) {
                        ForEach(["Starbase", "Embassy", "Dilithium Mine", "Spire", "Research Lab", "Colony World", "Armada", "Other"], id: \.self) { Text($0) }
                    }
                    TextField("Project name", text: $item.project)
                    TextField("Resource", text: $item.resource)
                    Stepper("Current contribution: \(item.current)", value: $item.current, in: 0...999999999)
                    Stepper("Target contribution: \(item.target)", value: $item.target, in: 0...999999999)
                    Toggle("Set target date", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Target date", selection: Binding(get: { item.deadline ?? Date() }, set: { item.deadline = $0 }), displayedComponents: .date)
                    }
                }
                Section("Notes") { TextEditor(text: $item.notes).frame(minHeight: 80) }
            }
            .onAppear { hasDeadline = item.deadline != nil }
            .onChange(of: hasDeadline) { _, enabled in if !enabled { item.deadline = nil } }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Fleet Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveFleetProject(item); dismiss() }
                        .disabled(item.project.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }
}

// MARK: - Exchange price notebook

struct ExchangeNotebookView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = ProgressionEconomyStore.shared
    @State private var editing: ExchangePriceRecord?
    @State private var showingEditor = false

    var body: some View {
        List {
            Section {
                Button { editing = nil; showingEditor = true } label: {
                    Label("Record exchange price", systemImage: "plus.circle.fill")
                }.listRowBackground(theme.surface)
                Text("Manually record observed buy and sell prices. Spread and batch totals are arithmetic estimates, not live Exchange listings or guaranteed profit.")
                    .font(.caption).foregroundStyle(.secondary).listRowBackground(theme.surface)
            }
            Section("Price notebook • \(store.exchangeItems.count)") {
                if store.exchangeItems.isEmpty {
                    ContentUnavailableView("No prices recorded", systemImage: "chart.line.uptrend.xyaxis", description: Text("Add an item and record the prices you observe in-game."))
                        .listRowBackground(theme.surface)
                }
                ForEach(store.exchangeItems) { item in
                    Button { editing = item; showingEditor = true } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.item).font(.headline).foregroundStyle(.white)
                                Spacer()
                                Text(item.category.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(theme.secondaryAccent)
                            }
                            HStack {
                                priceColumn("BUY", value: item.buyPrice)
                                Spacer()
                                priceColumn("SELL", value: item.sellPrice)
                                Spacer()
                                priceColumn("SPREAD", value: item.spread)
                            }
                            Text("Batch of \(item.quantity): \(item.totalBuyCost.formatted()) buy • \(item.totalSellValue.formatted()) sell")
                                .font(.caption2).foregroundStyle(theme.accent)
                            Text("Updated \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.white.opacity(0.5))
                        }
                    }.listRowBackground(theme.surface)
                    .swipeActions { Button(role: .destructive) { store.deleteExchangeItem(item) } label: { Label("Delete", systemImage: "trash") } }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .sheet(isPresented: $showingEditor) {
            ExchangePriceEditorView(item: editing ?? ExchangePriceRecord(item: "", category: "Equipment", buyPrice: 0, sellPrice: 0, quantity: 1, notes: ""))
        }
    }

    private func priceColumn(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(theme.secondaryAccent)
            Text(value.formatted()).font(.system(.caption, design: .monospaced, weight: .semibold)).foregroundStyle(.white)
        }
    }
}

private struct ExchangePriceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = ProgressionEconomyStore.shared
    @State var item: ExchangePriceRecord

    var body: some View {
        NavigationStack {
            Form {
                Section("Market observation") {
                    TextField("Item name", text: $item.item)
                    Picker("Category", selection: $item.category) {
                        ForEach(["Equipment", "Ship", "Trait", "Console", "Weapon", "Crafting", "Other"], id: \.self) { Text($0) }
                    }
                    Stepper("Observed buy price: \(item.buyPrice.formatted()) EC", value: $item.buyPrice, in: 0...2000000000, step: 1000)
                    Stepper("Observed sell price: \(item.sellPrice.formatted()) EC", value: $item.sellPrice, in: 0...2000000000, step: 1000)
                    Stepper("Quantity: \(item.quantity)", value: $item.quantity, in: 1...999999)
                }
                Section("Notes") { TextEditor(text: $item.notes).frame(minHeight: 80) }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Exchange Price")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveExchangeItem(item); dismiss() }
                        .disabled(item.item.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }
}
