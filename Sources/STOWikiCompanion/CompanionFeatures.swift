import SwiftUI
import Foundation
import Combine

// MARK: - Persistent companion data

struct WikiSavedPage: Identifiable, Codable, Hashable {
    var id: String { title }
    let title: String
    var snippet: String
    var extract: String?
    var savedAt: Date
    var sourceURL: URL {
        URL(string: "https://stowiki.net/wiki/" + title.replacingOccurrences(of: " ", with: "_"))!
    }
}

struct ShipBuild: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var ship: String
    var captain: String
    var role: String
    var weapons: String
    var consoles: String
    var traits: String
    var notes: String
    var updatedAt = Date()
}

struct CaptainProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var faction: String
    var career: String
    var specialization: String
    var notes: String
}

struct ProgressRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var category: String
    var detail: String
    var isComplete = false
}

@MainActor
final class CompanionStore: ObservableObject {
    static let shared = CompanionStore()

    @Published private(set) var bookmarks: [WikiSavedPage] = []
    @Published private(set) var history: [String] = []
    @Published private(set) var builds: [ShipBuild] = []
    @Published private(set) var captains: [CaptainProfile] = []
    @Published private(set) var progress: [ProgressRecord] = []

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        bookmarks = load([WikiSavedPage].self, key: "companion.bookmarks") ?? []
        history = defaults.stringArray(forKey: "companion.history") ?? []
        builds = load([ShipBuild].self, key: "companion.builds") ?? []
        captains = load([CaptainProfile].self, key: "companion.captains") ?? []
        progress = load([ProgressRecord].self, key: "companion.progress") ?? Self.defaultProgress
    }

    private static let defaultProgress: [ProgressRecord] = [
        ProgressRecord(title: "Daily Endeavors", category: "Endeavor", detail: "Track daily and universal endeavor objectives"),
        ProgressRecord(title: "Reputation Projects", category: "Reputation", detail: "Record active hourly and daily reputation projects"),
        ProgressRecord(title: "Featured Episode", category: "Mission", detail: "Keep your current featured episode progress"),
        ProgressRecord(title: "Event Campaign", category: "Event", detail: "Track event progress and reward claims")
    ]

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    func recordSearch(_ term: String) {
        let value = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        history.removeAll { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }
        history.insert(value, at: 0)
        history = Array(history.prefix(30))
        defaults.set(history, forKey: "companion.history")
    }

    func clearHistory() {
        history = []
        defaults.removeObject(forKey: "companion.history")
    }

    func isBookmarked(_ title: String) -> Bool {
        bookmarks.contains { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
    }

    func toggleBookmark(title: String, snippet: String = "", extract: String? = nil) {
        if let index = bookmarks.firstIndex(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.insert(WikiSavedPage(title: title, snippet: snippet, extract: extract, savedAt: Date()), at: 0)
        }
        save(bookmarks, key: "companion.bookmarks")
    }

    func updateOfflineText(title: String, extract: String) {
        guard let index = bookmarks.firstIndex(where: { $0.title == title }) else { return }
        bookmarks[index].extract = extract
        save(bookmarks, key: "companion.bookmarks")
    }

    func saveBuild(_ build: ShipBuild) {
        if let index = builds.firstIndex(where: { $0.id == build.id }) { builds[index] = build }
        else { builds.insert(build, at: 0) }
        save(builds, key: "companion.builds")
    }

    func deleteBuild(_ build: ShipBuild) {
        builds.removeAll { $0.id == build.id }
        save(builds, key: "companion.builds")
    }

    func saveCaptain(_ captain: CaptainProfile) {
        if let index = captains.firstIndex(where: { $0.id == captain.id }) { captains[index] = captain }
        else { captains.insert(captain, at: 0) }
        save(captains, key: "companion.captains")
    }

    func deleteCaptain(_ captain: CaptainProfile) {
        captains.removeAll { $0.id == captain.id }
        save(captains, key: "companion.captains")
    }

    func toggleProgress(_ item: ProgressRecord) {
        guard let index = progress.firstIndex(where: { $0.id == item.id }) else { return }
        progress[index].isComplete.toggle()
        save(progress, key: "companion.progress")
    }

    func addProgress(_ item: ProgressRecord) {
        progress.insert(item, at: 0)
        save(progress, key: "companion.progress")
    }

    func deleteProgress(_ item: ProgressRecord) {
        progress.removeAll { $0.id == item.id }
        save(progress, key: "companion.progress")
    }
}

// MARK: - Companion hub

struct CompanionHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @StateObject private var store = CompanionStore.shared
    @State private var selectedSection = "Overview"

    private let sections = [
        ("Overview", "square.grid.2x2"),
        ("Offline Wiki", "bookmark"),
        ("Starships", "airplane"),
        ("Traits & Gear", "sparkles"),
        ("Build Planner", "wrench.and.screwdriver"),
        ("Captains", "person.crop.rectangle.stack"),
        ("Duty Officers", "person.3"),
        ("Cooldowns", "timer"),
        ("Inventory", "shippingbox"),
        ("Progress", "checklist")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(sections.enumerated()), id: \.offset) { entry in
                                let section = entry.element
                                Button {
                                    selectedSection = section.0
                                } label: {
                                    Label(section.0, systemImage: section.1)
                                        .font(.system(.caption, design: .rounded, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(selectedSection == section.0 ? theme.accent : theme.surface, in: Capsule())
                                        .foregroundStyle(selectedSection == section.0 ? theme.background : .white.opacity(0.82))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    Group {
                        switch selectedSection {
                        case "Offline Wiki": OfflineLibraryView()
                        case "Starships": StarshipCatalogView()
                        case "Traits & Gear": TraitsEquipmentLibraryView()
                        case "Build Planner": BuildPlannerView()
                        case "Captains": CaptainRosterView()
                        case "Duty Officers": DutyOfficerRosterView()
                        case "Cooldowns": CooldownPlannerView()
                        case "Inventory": InventoryChecklistView()
                        case "Progress": ProgressTrackerView()
                        default: CompanionOverviewView(onSelect: { selectedSection = $0 })
                        }
                    }
                }
            }
            .navigationTitle("Companion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(theme.accent)
                }
            }
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

private struct CompanionOverviewView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = CompanionStore.shared
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CAPTAIN'S READY ROOM")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .tracking(1.8).foregroundStyle(theme.secondaryAccent)
                    Text("Your STO command center")
                        .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("Keep your reference material, ship configurations, captains, and goals together on this device.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.68))
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metric("Saved pages", value: store.bookmarks.count, icon: "bookmark")
                    metric("Saved builds", value: store.builds.count, icon: "wrench.and.screwdriver")
                    metric("Captains", value: store.captains.count, icon: "person.2")
                    metric("Open goals", value: store.progress.filter { !$0.isComplete }.count, icon: "checklist")
                }
                VStack(spacing: 9) {
                    dashboardLink("Offline Wiki", subtitle: "Bookmarks, cached articles, recent searches", icon: "book.closed")
                    dashboardLink("Starships", subtitle: "Browse a starter catalog and jump to wiki records", icon: "airplane")
                    dashboardLink("Traits & Gear", subtitle: "Quick-reference traits, consoles, weapons, and equipment", icon: "sparkles")
                    dashboardLink("Build Planner", subtitle: "Save weapons, consoles, traits, and notes", icon: "wrench.and.screwdriver")
                    dashboardLink("Captains", subtitle: "Maintain multiple character profiles", icon: "person.crop.rectangle.stack")
                    dashboardLink("Duty Officers", subtitle: "Roster, department, rarity, and assignments", icon: "person.3")
                    dashboardLink("Cooldowns", subtitle: "Custom timers for projects, crafting, and events", icon: "timer")
                    dashboardLink("Inventory", subtitle: "Track resources and target quantities", icon: "shippingbox")
                    dashboardLink("Progress", subtitle: "Track missions, endeavors, events, and reputation", icon: "checklist")
                }
            }
            .padding(18)
        }
    }

    private func metric(_ title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(theme.accent)
            Text("\(value)").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(title.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.8).foregroundStyle(theme.secondaryAccent)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dashboardLink(_ title: String, subtitle: String, icon: String) -> some View {
        Button { onSelect(title) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(theme.accent).frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(theme.secondaryAccent)
            }
            .padding(14).background(theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }.buttonStyle(.plain)
    }
}

private struct OfflineLibraryView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = CompanionStore.shared
    @State private var downloading: Set<String> = []
    @State private var downloadErrors: [String: String] = [:]

    var body: some View {
        List {
            Section("Saved wiki pages") {
                if store.bookmarks.isEmpty {
                    ContentUnavailableView("No saved pages", systemImage: "bookmark", description: Text("Bookmark pages from search results to keep them here."))
                        .listRowBackground(theme.surface)
                }
                ForEach(store.bookmarks) { page in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(page.title).font(.headline).foregroundStyle(.white)
                        Text(page.extract ?? page.snippet).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(3)
                        HStack {
                            Label(page.extract == nil ? "Snippet saved" : "Offline text saved", systemImage: page.extract == nil ? "text.alignleft" : "checkmark.icloud")
                            Spacer()
                            if page.extract == nil {
                                Button {
                                    Task { await cacheArticle(page) }
                                } label: {
                                    if downloading.contains(page.title) {
                                        ProgressView().tint(theme.accent)
                                    } else {
                                        Label("Save offline", systemImage: "arrow.down.circle")
                                    }
                                }
                                .disabled(downloading.contains(page.title))
                            } else {
                                Label("Available offline", systemImage: "checkmark.circle.fill")
                            }
                            Link("Open", destination: page.sourceURL)
                        }.font(.caption2).foregroundStyle(theme.accent)
                        if let error = downloadErrors[page.title] {
                            Text(error).font(.caption2).foregroundStyle(.red)
                        }
                    }
                    .listRowBackground(theme.surface)
                    .swipeActions {
                        Button(role: .destructive) { store.toggleBookmark(title: page.title) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }
            Section {
                Button("Clear search history", role: .destructive) { store.clearHistory() }
                if store.history.isEmpty {
                    Text("No recent searches").foregroundStyle(.secondary)
                } else {
                    ForEach(store.history, id: \.self) { term in
                        Label(term, systemImage: "clock").listRowBackground(theme.surface)
                    }
                }
            } header: { Text("Recent searches") }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .tint(theme.accent)
    }

    @MainActor
    private func cacheArticle(_ page: WikiSavedPage) async {
        downloading.insert(page.title)
        downloadErrors[page.title] = nil
        defer { downloading.remove(page.title) }

        var components = URLComponents(string: "https://stowiki.net/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "titles", value: page.title),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ]
        guard let url = components.url else {
            downloadErrors[page.title] = "Could not create the wiki request."
            return
        }
        do {
            var request = URLRequest(url: url)
            request.setValue("STOWikiCompanion/1.0 (read-only iOS client)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let payload = try JSONDecoder().decode(OfflineExtractResponse.self, from: data)
            guard let extract = payload.query?.pages.first?.extract, !extract.isEmpty else {
                downloadErrors[page.title] = "The wiki returned no article text."
                return
            }
            store.updateOfflineText(title: page.title, extract: extract)
        } catch {
            downloadErrors[page.title] = "Could not cache this article. Check your connection and retry."
        }
    }
}

private struct OfflineExtractResponse: Decodable {
    struct Query: Decodable {
        struct Page: Decodable {
            let extract: String?
        }
        let pages: [Page]
    }
    let query: Query?
}

private struct StarshipCatalogView: View {
    @Environment(\.interfaceTheme) private var theme
    @State private var search = ""
    private let ships: [(String, String, String)] = [
        ("Constitution-class", "Federation", "Classic exploration cruiser"),
        ("Galaxy-class", "Federation", "Exploration and command cruiser"),
        ("Defiant-class", "Federation", "Escort and tactical combat vessel"),
        ("Intrepid-class", "Federation", "Long-range science vessel"),
        ("Sovereign-class", "Federation", "Advanced assault cruiser"),
        ("Odyssey-class", "Federation", "Flagship operations cruiser"),
        ("Odyssey-class variants", "Federation", "Flagship family and variants"),
        ("Bird-of-Prey", "Klingon", "Maneuverable raider family"),
        ("Vor'cha-class", "Klingon", "Attack cruiser"),
        ("Negh'Var-class", "Klingon", "Heavy battle cruiser"),
        ("D'deridex-class", "Romulan", "Warbird family"),
        ("Mogai-class", "Romulan", "Heavy warbird"),
        ("Jem'Hadar Attack Ship", "Dominion", "Fast attack craft"),
        ("Jem'Hadar Dreadnought Carrier", "Dominion", "Carrier platform"),
        ("Universe-class", "Federation", "Temporal heavy dreadnought")
    ]

    private var filtered: [(String, String, String)] {
        ships.filter { search.isEmpty || ($0.0 + $0.1 + $0.2).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section {
                TextField("Search ship classes…", text: $search)
                    .listRowBackground(theme.surface)
            } header: { Text("Ship registry • starter index") }
            Section("Known classes") {
                ForEach(Array(filtered.enumerated()), id: \.offset) { entry in
                    let ship = entry.element
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ship.0).font(.headline).foregroundStyle(.white)
                        Text("\(ship.1) • \(ship.2)").font(.caption).foregroundStyle(.white.opacity(0.62))
                        Link("View STO Wiki record", destination: URL(string: "https://stowiki.net/wiki/" + ship.0.replacingOccurrences(of: " ", with: "_"))!)
                            .font(.caption.weight(.semibold))
                    }.listRowBackground(theme.surface)
                }
            }
            Section {
                Text("This is a curated starter index, not a complete or authoritative in-game ship database. Use the wiki links for current acquisition, stats, variants, and availability.")
                    .font(.caption).foregroundStyle(.secondary).listRowBackground(theme.surface)
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
    }
}

private struct TraitsEquipmentLibraryView: View {
    @Environment(\.interfaceTheme) private var theme
    @State private var search = ""

    private let categories: [(String, String, String, [String])] = [
        ("Traits", "sparkles", "Personal, starship, reputation, and space traits", ["Personal Traits", "Starship Traits", "Space Reputation Traits", "Ground Traits"]),
        ("Weapons", "scope", "Energy weapons, projectiles, and firing modes", ["Energy Weapons", "Beam Arrays", "Dual Cannons", "Torpedoes"]),
        ("Consoles", "square.grid.3x3", "Engineering, science, tactical, and universal consoles", ["Engineering Consoles", "Science Consoles", "Tactical Consoles", "Universal Consoles"]),
        ("Equipment", "shippingbox", "Deflectors, engines, shields, and devices", ["Deflectors", "Impulse Engines", "Shields", "Devices", "Hangar Pets"]),
        ("Reputation", "medal", "Reputation systems and set equipment", ["Reputation System", "Reputation Projects", "Reputation Equipment"])
    ]

    var body: some View {
        List {
            Section {
                TextField("Find a trait or equipment category…", text: $search)
                    .listRowBackground(theme.surface)
            } header: { Text("Reference library") }
            ForEach(Array(categories.filter { category in
                search.isEmpty || (category.0 + category.2 + category.3.joined(separator: " ")).localizedCaseInsensitiveContains(search)
            }.enumerated()), id: \.offset) { entry in
                let category = entry.element
                Section {
                    ForEach(category.3.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { item in
                        Link(destination: URL(string: "https://stowiki.net/wiki/" + item.replacingOccurrences(of: " ", with: "_"))!) {
                            HStack {
                                Text(item).foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(theme.accent)
                            }
                        }
                        .listRowBackground(theme.surface)
                    }
                } header: {
                    Label(category.0, systemImage: category.1)
                } footer: {
                    Text(category.2)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .tint(theme.accent)
    }
}

private struct BuildPlannerView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = CompanionStore.shared
    @State private var editing: ShipBuild?
    @State private var showingEditor = false

    var body: some View {
        List {
            Section {
                Button { editing = nil; showingEditor = true } label: {
                    Label("Create ship build", systemImage: "plus.circle.fill").font(.headline)
                }.listRowBackground(theme.surface)
            }
            Section("Saved configurations") {
                if store.builds.isEmpty {
                    Text("No builds yet. Create a configuration to record your ship, role, weapons, consoles, traits, and notes.")
                        .font(.subheadline).foregroundStyle(.secondary).listRowBackground(theme.surface)
                }
                ForEach(store.builds) { build in
                    Button { editing = build; showingEditor = true } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(build.name).font(.headline).foregroundStyle(.white)
                            Text("\(build.ship) • \(build.role)").font(.caption).foregroundStyle(theme.secondaryAccent)
                            Text(build.captain.isEmpty ? "No captain assigned" : build.captain).font(.caption2).foregroundStyle(.white.opacity(0.55))
                        }
                    }.listRowBackground(theme.surface)
                    .swipeActions {
                        Button(role: .destructive) { store.deleteBuild(build) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .sheet(isPresented: $showingEditor) {
            BuildEditorView(build: editing ?? ShipBuild(name: "", ship: "", captain: "", role: "Damage", weapons: "", consoles: "", traits: "", notes: ""))
        }
    }
}

private struct BuildEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = CompanionStore.shared
    @State var build: ShipBuild

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    TextField("Build name", text: $build.name)
                    TextField("Ship", text: $build.ship)
                    TextField("Captain", text: $build.captain)
                    Picker("Role", selection: $build.role) {
                        ForEach(["Damage", "Tank", "Science", "Support", "Cannon", "Beam", "Exotic", "Torpedo", "Hybrid"], id: \.self) { Text($0) }
                    }
                }
                Section("Loadout") {
                    TextField("Weapons and firing modes", text: $build.weapons, axis: .vertical).lineLimit(2...5)
                    TextField("Consoles", text: $build.consoles, axis: .vertical).lineLimit(3...8)
                    TextField("Traits (ship, personal, reputation)", text: $build.traits, axis: .vertical).lineLimit(3...8)
                }
                Section("Notes") {
                    TextEditor(text: $build.notes).frame(minHeight: 110)
                }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Ship Build")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        build.updatedAt = Date()
                        store.saveBuild(build)
                        dismiss()
                    }.disabled(build.name.trimmingCharacters(in: .whitespaces).isEmpty || build.ship.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .tint(theme.accent).preferredColorScheme(.dark)
    }
}

private struct CaptainRosterView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = CompanionStore.shared
    @State private var showingEditor = false
    @State private var editing: CaptainProfile?

    var body: some View {
        List {
            Section {
                Button { editing = nil; showingEditor = true } label: { Label("Add captain", systemImage: "plus.circle.fill") }
                    .listRowBackground(theme.surface)
            }
            Section("Character roster") {
                if store.captains.isEmpty {
                    Text("Create a profile for each character to keep faction, career, specialization, and notes organized.")
                        .font(.subheadline).foregroundStyle(.secondary).listRowBackground(theme.surface)
                }
                ForEach(store.captains) { captain in
                    Button { editing = captain; showingEditor = true } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(captain.name).font(.headline).foregroundStyle(.white)
                            Text("\(captain.faction) • \(captain.career)").font(.caption).foregroundStyle(theme.secondaryAccent)
                            Text(captain.specialization).font(.caption2).foregroundStyle(.white.opacity(0.58))
                        }
                    }.listRowBackground(theme.surface)
                    .swipeActions { Button(role: .destructive) { store.deleteCaptain(captain) } label: { Label("Delete", systemImage: "trash") } }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .sheet(isPresented: $showingEditor) {
            CaptainEditorView(captain: editing ?? CaptainProfile(name: "", faction: "Federation", career: "Tactical", specialization: "", notes: ""))
        }
    }
}

private struct CaptainEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = CompanionStore.shared
    @State var captain: CaptainProfile

    var body: some View {
        NavigationStack {
            Form {
                Section("Captain identity") {
                    TextField("Character name", text: $captain.name)
                    Picker("Faction", selection: $captain.faction) {
                        ForEach(["Federation", "Klingon", "Romulan Republic", "Dominion", "Other"], id: \.self) { Text($0) }
                    }
                    Picker("Career", selection: $captain.career) {
                        ForEach(["Tactical", "Engineering", "Science"], id: \.self) { Text($0) }
                    }
                    TextField("Primary specialization", text: $captain.specialization)
                }
                Section("Notes") { TextEditor(text: $captain.notes).frame(minHeight: 100) }
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .navigationTitle("Captain Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveCaptain(captain); dismiss() }
                        .disabled(captain.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }.tint(theme.accent).preferredColorScheme(.dark)
    }
}

private struct ProgressTrackerView: View {
    @Environment(\.interfaceTheme) private var theme
    @ObservedObject private var store = CompanionStore.shared
    @State private var title = ""
    @State private var category = "Mission"
    @State private var detail = ""
    @State private var showingAdd = false

    var body: some View {
        List {
            Section {
                Button { showingAdd = true } label: { Label("Add mission or goal", systemImage: "plus.circle.fill") }
                    .listRowBackground(theme.surface)
            }
            Section("Objectives") {
                ForEach(store.progress) { item in
                    Button { store.toggleProgress(item) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isComplete ? theme.accent : theme.secondaryAccent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).foregroundStyle(.white).strikethrough(item.isComplete)
                                Text("\(item.category) • \(item.detail)").font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                            }
                            Spacer()
                        }
                    }.listRowBackground(theme.surface)
                    .swipeActions {
                        Button(role: .destructive) { store.deleteProgress(item) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(theme.background).tint(theme.accent)
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                Form {
                    TextField("Objective name", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(["Mission", "Reputation", "Endeavor", "Event", "Campaign", "Other"], id: \.self) { Text($0) }
                    }
                    TextField("Details or target", text: $detail, axis: .vertical).lineLimit(2...4)
                }
                .navigationTitle("New Objective")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAdd = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            store.addProgress(ProgressRecord(title: title, category: category, detail: detail))
                            title = ""; detail = ""; showingAdd = false
                        }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }.tint(theme.accent).preferredColorScheme(.dark)
        }
    }
}
