import SwiftUI
import Foundation

@main
struct STOWikiCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            WikiSearchView().preferredColorScheme(.dark)
        }
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
    }

    var url: URL {
        let slug = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        return URL(string: "https://stowiki.net/wiki/" + slug)!
    }
}

struct WikiSearchView: View {
    @State private var searchText = ""
    @State private var results: [SearchHit] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Searching STO Wiki…")
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't reach the wiki", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                } else if results.isEmpty {
                    ContentUnavailableView("Search STO Wiki", systemImage: "magnifyingglass", description: Text("Search ships, traits, equipment, missions, and more."))
                } else {
                    List(results) { hit in
                        Link(destination: hit.url) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(hit.title).font(.headline).foregroundStyle(.primary)
                                if !hit.readableSnippet.isEmpty {
                                    Text(hit.readableSnippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                }
                                if let words = hit.wordcount {
                                    Text(String(words) + " words").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }.padding(.vertical, 5)
                        }
                        .listRowBackground(Color(red: 0.05, green: 0.075, blue: 0.12))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(red: 0.025, green: 0.04, blue: 0.075))
            .navigationTitle("STO Wiki")
            .searchable(text: $searchText, prompt: "Ships, gear, traits…")
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await search() } } label: {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(.cyan)
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
        } catch {
            results = []
            errorMessage = "The API may be unavailable or may require different access settings. " + error.localizedDescription
        }
    }
}
