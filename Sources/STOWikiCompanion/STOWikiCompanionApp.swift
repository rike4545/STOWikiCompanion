import SwiftUI
import Foundation
import GoogleMobileAds

@main
struct STOWikiCompanionApp: App {
    @AppStorage("appearance.theme") private var selectedTheme = InterfaceTheme.lcars.rawValue

    var body: some Scene {
        WindowGroup {
            WikiSearchView()
                .environment(\.interfaceTheme, InterfaceTheme(rawValue: selectedTheme) ?? .lcars)
                .preferredColorScheme(.dark)
                .task { await AdMobConsentManager.shared.startIfNeeded() }
        }
    }
}

enum InterfaceTheme: String, CaseIterable, Identifiable {
    case lcars
    case starfleet
    case hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lcars: return "Classic LCARS"
        case .starfleet: return "Modern Starfleet"
        case .hybrid: return "LCARS Hybrid"
        }
    }

    var subtitle: String {
        switch self {
        case .lcars: return "Classic amber, gold, and violet computer panels"
        case .starfleet: return "Cool blue systems and cyan highlights"
        case .hybrid: return "Classic Star Trek character with modern iOS polish"
        }
    }

    var symbol: String {
        switch self {
        case .lcars: return "rectangle.roundedtop"
        case .starfleet: return "sparkles"
        case .hybrid: return "square.grid.2x2"
        }
    }

    var background: Color {
        switch self {
        case .lcars: return Color(red: 0.035, green: 0.025, blue: 0.065)
        case .starfleet: return Color(red: 0.018, green: 0.045, blue: 0.085)
        case .hybrid: return Color(red: 0.025, green: 0.035, blue: 0.070)
        }
    }

    var surface: Color {
        switch self {
        case .lcars: return Color(red: 0.105, green: 0.075, blue: 0.145)
        case .starfleet: return Color(red: 0.045, green: 0.095, blue: 0.155)
        case .hybrid: return Color(red: 0.055, green: 0.070, blue: 0.125)
        }
    }

    var accent: Color {
        switch self {
        case .lcars: return Color(red: 1.0, green: 0.62, blue: 0.28)
        case .starfleet: return Color(red: 0.28, green: 0.78, blue: 1.0)
        case .hybrid: return Color(red: 1.0, green: 0.66, blue: 0.30)
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .lcars: return Color(red: 0.75, green: 0.55, blue: 0.95)
        case .starfleet: return Color(red: 0.25, green: 0.92, blue: 0.92)
        case .hybrid: return Color(red: 0.45, green: 0.78, blue: 1.0)
        }
    }

    var panelShape: AnyShape {
        switch self {
        case .lcars: return AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        case .starfleet: return AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .hybrid: return AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct InterfaceThemeKey: EnvironmentKey {
    static let defaultValue = InterfaceTheme.lcars
}

extension EnvironmentValues {
    var interfaceTheme: InterfaceTheme {
        get { self[InterfaceThemeKey.self] }
        set { self[InterfaceThemeKey.self] = newValue }
    }
}

private struct SearchResponse: Decodable {
    let query: QueryPayload?
    struct QueryPayload: Decodable {
        let search: [SearchHit]?
    }
}

private struct SearchHit: Decodable, Identifiable {
    let title: String
    let snippet: String?
    let wordcount: Int?
    var id: String { title }

    var readableSnippet: String {
        (snippet ?? "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    var url: URL {
        var components = URLComponents(string: "https://stowiki.net/wiki/")!
        components.path += title.replacingOccurrences(of: " ", with: "_")
        return components.url!
    }
}

struct WikiSearchView: View {
    @Environment(\.interfaceTheme) private var theme
    @AppStorage("appearance.theme") private var selectedTheme = InterfaceTheme.lcars.rawValue
    @State private var searchText = ""
    @State private var results: [SearchHit] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAppearance = false
    @State private var showingBardArchive = false
    @State private var titleTapCount = 0

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    Group {
                        if isLoading {
                            VStack(spacing: 14) {
                                ProgressView().tint(theme.accent).scaleEffect(1.15)
                                Text("QUERYING STARFLEET DATABASE")
                                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                                    .tracking(1.4)
                                    .foregroundStyle(theme.secondaryAccent)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let errorMessage {
                            ContentUnavailableView(
                                "Database Unavailable",
                                systemImage: "antenna.radiowaves.left.and.right.slash",
                                description: Text(errorMessage)
                            )
                            .foregroundStyle(.white)
                        } else if results.isEmpty {
                            emptyState
                        } else {
                            resultList
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .sheet(isPresented: $showingAppearance) {
                AppearanceSettingsView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingBardArchive) {
                BardArchiveView()
            }
        }
        .tint(theme.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Capsule().fill(theme.accent).frame(width: 26, height: 5)
                        Capsule().fill(theme.secondaryAccent).frame(width: 12, height: 5)
                        Capsule().fill(theme.accent.opacity(0.55)).frame(width: 7, height: 5)
                    }

                    Text("STARFLEET DATABASE")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .tracking(2.2)
                        .foregroundStyle(theme.secondaryAccent)

                    Text("STO Wiki")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            titleTapCount += 1
                            if titleTapCount >= 7 {
                                titleTapCount = 0
                                showingBardArchive = true
                            }
                        }
                        .accessibilityHint("Tap seven times to reveal a hidden archive.")
                }

                Spacer(minLength: 0)

                Button {
                    showingAppearance = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 46, height: 46)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(theme.accent.opacity(0.35), lineWidth: 1)
                        }
                }
                .accessibilityLabel("Appearance settings")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.accent)
                TextField("Search ships, gear, traits…", text: $searchText)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        results = []
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .accessibilityLabel("Clear search")
                }
                Button {
                    Task { await search() }
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.background)
                        .frame(width: 36, height: 36)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .opacity(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                .accessibilityLabel("Search STO Wiki")
            }
            .padding(8)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.secondaryAccent.opacity(0.35), lineWidth: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(theme.accent)
                        .frame(width: 58, height: 58)
                        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Knowledge at your fingertips")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Search the Star Trek Online community wiki.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: theme.panelShape)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.accent)
                        .frame(width: 4)
                        .padding(.vertical, 14)
                }

                Text("QUICK REFERENCE")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(theme.secondaryAccent)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    quickSearch("Starships", symbol: "airplane", query: "starship")
                    quickSearch("Traits", symbol: "sparkles", query: "trait")
                    quickSearch("Equipment", symbol: "wrench.and.screwdriver", query: "equipment")
                    quickSearch("Missions", symbol: "map", query: "mission")
                }

                NativeAdCard()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    private func quickSearch(_ title: String, symbol: String, query: String) -> some View {
        Button {
            searchText = query
            Task { await search() }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(theme.accent)
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                HStack {
                    Text("ACCESS FILES")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(theme.secondaryAccent.opacity(0.85))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: theme.panelShape)
            .overlay {
                theme.panelShape.stroke(theme.secondaryAccent.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                HStack {
                    Text("SEARCH RESULTS")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(theme.secondaryAccent)
                    Spacer()
                    Text("\(results.count) RECORDS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.48))
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 3)

                ForEach(Array(results.enumerated()), id: \.element.id) { index, hit in
                    Link(destination: hit.url) {
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.accent)
                                .frame(width: 4)
                                .padding(.vertical, 3)

                            VStack(alignment: .leading, spacing: 7) {
                                Text(hit.title)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)

                                if !hit.readableSnippet.isEmpty {
                                    Text(hit.readableSnippet)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.68))
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }

                                if let words = hit.wordcount {
                                    Text("\(words) WORDS")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .tracking(0.7)
                                        .foregroundStyle(theme.secondaryAccent)
                                }
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(theme.accent)
                                .padding(.top, 3)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface, in: theme.panelShape)
                        .overlay {
                            theme.panelShape.stroke(theme.secondaryAccent.opacity(0.16), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)

                    if index == 2 {
                        NativeAdCard()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(isLoading ? theme.accent : theme.secondaryAccent).frame(width: 6, height: 6)
            Text(isLoading ? "QUERY IN PROGRESS" : "COMMUNITY DATABASE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(theme.title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(theme.background.opacity(0.97))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.secondaryAccent.opacity(0.22)).frame(height: 1)
        }
    }

    @MainActor
    private func search() async {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var components = URLComponents(string: "https://stowiki.net/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: term),
            URLQueryItem(name: "srlimit", value: "30"),
            URLQueryItem(name: "srprop", value: "snippet|wordcount"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ]
        guard let url = components.url else {
            errorMessage = "Invalid search URL."
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
            results = try JSONDecoder().decode(SearchResponse.self, from: data).query?.search ?? []
            if results.isEmpty {
                errorMessage = nil
            }
        } catch {
            results = []
            errorMessage = "The wiki API may be temporarily unavailable. \(error.localizedDescription)"
        }
    }
}

private struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @AppStorage("appearance.theme") private var selectedTheme = InterfaceTheme.lcars.rawValue
    @ObservedObject private var consentManager = AdMobConsentManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CHOOSE YOUR INTERFACE")
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .tracking(1.8)
                                .foregroundStyle(theme.secondaryAccent)
                            Text("Appearance")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Select a Starfleet computer style. Your choice is saved on this device and applied throughout the app.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.68))
                        }

                        ForEach(InterfaceTheme.allCases) { option in
                            themeCard(option)
                        }

                        if consentManager.privacyOptionsRequired {
                            Button {
                                Task { await consentManager.presentPrivacyOptions() }
                            } label: {
                                Label("Privacy & Ad Choices", systemImage: "hand.raised")
                                    .font(.system(.headline, design: .rounded))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(15)
                                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                            .foregroundStyle(theme.accent)
                            .accessibilityHint("Review or change your advertising privacy choices.")
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.accent)
                }
            }
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func themeCard(_ option: InterfaceTheme) -> some View {
        let isSelected = selectedTheme == option.rawValue

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTheme = option.rawValue
            }
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 5) {
                    HStack(spacing: 3) {
                        Capsule().fill(option.accent).frame(height: 7)
                        Capsule().fill(option.secondaryAccent).frame(width: 15, height: 7)
                    }
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3).fill(option.secondaryAccent).frame(width: 15, height: 21)
                        RoundedRectangle(cornerRadius: 3).fill(option.accent.opacity(0.8)).frame(height: 21)
                    }
                }
                .padding(10)
                .frame(width: 78, height: 60)
                .background(option.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSelected ? option.accent : .white.opacity(0.3))
            }
            .padding(13)
            .background(option.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? option.accent : option.secondaryAccent.opacity(0.16), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
