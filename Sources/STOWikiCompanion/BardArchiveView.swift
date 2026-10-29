import SwiftUI
import Foundation

private struct BardPoem: Decodable, Identifiable {
    let title: String
    let lines: [String]

    var id: String { title }

    var text: String { lines.joined(separator: "\n") }
}

struct BardArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.interfaceTheme) private var theme
    @State private var sonnets: [BardPoem] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let transmissions: [(title: String, subtitle: String, url: URL)] = [
        ("Holodeck Transmission 01", "A hidden transmission from the archive", URL(string: "https://www.youtube.com/watch?v=Beqh0b3iR_I&list=RDBeqh0b3iR_I&start_radio=1")!),
        ("Holodeck Transmission 02", "A second hidden transmission", URL(string: "https://www.youtube.com/watch?v=9t6MZ7hvzcY")!)
    ]

    private var filteredSonnets: [BardPoem] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return sonnets }
        return sonnets.filter {
            $0.title.localizedCaseInsensitiveContains(term)
                || $0.text.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        introCard
                        transmissionsSection
                        sonnetsSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Bard's Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await loadSonnets() }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.accent)
                Text("CLASSIFIED HOLODECK FILE")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(theme.secondaryAccent)
            }
            Text("The Bard's Archive")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("All 154 Shakespeare sonnets, plus two transmissions tucked away for curious crew members.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Text("SONNETS • EST. 1609")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(theme.accent)
                .padding(.top, 2)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: theme.panelShape)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.accent)
                .frame(width: 4)
                .padding(.vertical, 14)
        }
    }

    private var transmissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("HIDDEN TRANSMISSIONS", symbol: "play.rectangle")
            ForEach(Array(transmissions.enumerated()), id: \.offset) { _, item in
                Link(destination: item.url) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.background)
                            .frame(width: 42, height: 42)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(.white)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.secondaryAccent)
                    }
                    .padding(13)
                    .background(theme.surface, in: theme.panelShape)
                    .overlay { theme.panelShape.stroke(theme.secondaryAccent.opacity(0.18), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sonnetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeading("SHAKESPEARE'S SONNETS", symbol: "text.book.closed")
                Spacer()
                if !sonnets.isEmpty {
                    Text("\(sonnets.count) FILES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.accent)
                TextField("Search title or sonnet text…", text: $searchText)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(12)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.secondaryAccent.opacity(0.25), lineWidth: 1) }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(theme.accent)
                    Text("RETRIEVING SONNET ARCHIVE…")
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(theme.secondaryAccent)
                }
                .padding(.vertical, 16)
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Archive unavailable")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                    Button("Retry") { Task { await loadSonnets() } }
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.accent)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: theme.panelShape)
            } else if filteredSonnets.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .foregroundStyle(.white)
            } else {
                ForEach(filteredSonnets) { sonnet in
                    NavigationLink {
                        BardSonnetDetailView(sonnet: sonnet)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text(sonnetNumber(sonnet.title))
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundStyle(theme.background)
                                .frame(width: 38, height: 38)
                                .background(theme.secondaryAccent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(sonnet.title)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                Text(sonnet.lines.prefix(2).joined(separator: " "))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(theme.accent)
                                .padding(.top, 4)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface, in: theme.panelShape)
                        .overlay { theme.panelShape.stroke(theme.secondaryAccent.opacity(0.14), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Text retrieved from PoetryDB. Shakespeare's original sonnets are public domain; network access is required to load the collection.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.top, 4)
        }
    }

    private func sectionHeading(_ title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(theme.accent)
            Text(title)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(theme.secondaryAccent)
        }
    }

    private func sonnetNumber(_ title: String) -> String {
        let digits = title.filter(\.isNumber)
        return digits.isEmpty ? "SON" : String(digits.prefix(3))
    }

    @MainActor
    private func loadSonnets() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "https://poetrydb.org/author/Shakespeare/title,lines") else {
            errorMessage = "The archive address is invalid."
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let poems = try JSONDecoder().decode([BardPoem].self, from: data)
            let matches = poems.filter { $0.title.localizedCaseInsensitiveContains("sonnet") }
            guard !matches.isEmpty else {
                errorMessage = "The poetry service did not return the sonnet collection. Please try again later."
                return
            }
            sonnets = matches.sorted { sonnetSortNumber($0.title) < sonnetSortNumber($1.title) }
        } catch {
            errorMessage = "Could not connect to the public-domain sonnet source. Check your connection and try again."
        }
    }

    private func sonnetSortNumber(_ title: String) -> Int {
        let digits = title.filter(\.isNumber)
        return Int(digits) ?? Int.max
    }
}

private struct BardSonnetDetailView: View {
    @Environment(\.interfaceTheme) private var theme
    let sonnet: BardPoem

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(sonnet.title.uppercased())
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(theme.secondaryAccent)
                    Text(sonnet.text)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(6)
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("WILLIAM SHAKESPEARE • PUBLIC DOMAIN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(theme.accent)
                        .padding(.top, 8)
                }
                .padding(22)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Sonnet")
        .navigationBarTitleDisplayMode(.inline)
    }
}
