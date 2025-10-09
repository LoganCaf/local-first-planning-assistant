import SwiftUI
import MapKit
import Combine

struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PlaceSearchViewModel()

    let onSelect: (TaskLocation) -> Void

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isSearching {
                    ProgressView("검색 중…")
                }

                ForEach(viewModel.results) { result in
                    Button {
                        onSelect(result.taskLocation)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.name)
                                .font(.headline)
                            if let subtitle = result.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !viewModel.query.isEmpty && viewModel.results.isEmpty && !viewModel.isSearching {
                    Text("검색 결과가 없어요.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("장소 검색")
            .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "장소를 입력하세요")
            .onChange(of: viewModel.query) { _, newValue in
                viewModel.performSearch(query: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
    }
}

@MainActor
final class PlaceSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [PlaceSearchResult] = []
    @Published var isSearching = false

    private var searchTask: Task<Void, Never>?

    func performSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask = Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.resultTypes = [.pointOfInterest, .address]

            do {
                let response = try await MKLocalSearch(request: request).start()
                let mapped = response.mapItems.map { PlaceSearchResult(mapItem: $0) }
                await MainActor.run {
                    self.results = mapped
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.results = []
                    self.isSearching = false
                }
            }
        }
    }
}

struct PlaceSearchResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D
    let mapItemIdentifier: String?

    init(mapItem: MKMapItem) {
        self.name = mapItem.name ?? "알 수 없는 장소"
        subtitle = PlaceSearchResult.makeSubtitle(from: mapItem)
        coordinate = mapItem.placemark.coordinate
        mapItemIdentifier = mapItem.placemark.name
    }

    var taskLocation: TaskLocation {
        TaskLocation(
            name: name,
            subtitle: subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            mapItemIdentifier: mapItemIdentifier
        )
    }

    private static func makeSubtitle(from item: MKMapItem) -> String? {
        if let placemark = item.placemark as MKPlacemark? {
            if let locality = placemark.locality, let thoroughfare = placemark.thoroughfare, !locality.isEmpty, !thoroughfare.isEmpty {
                return "\(locality) \(thoroughfare)"
            }
            if let title = placemark.title, !title.isEmpty {
                return title
            }
        }
        return item.name
    }
}
