import SwiftUI
import SwiftData
import UIKit

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [MediaItem]

    @State private var searchText = ""
    @State private var searchScope: SearchScope = .all
    @State private var showDateFilter = false
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    @AppStorage("recentSearches") private var recentSearchesData: Data = Data()

    @State private var recentSearches: [String] = []

    private var filteredItems: [MediaItem] {
        var items = allItems

        if !searchText.isEmpty {
            items = items.filter { item in
                switch searchScope {
                case .all:
                    return item.memo.localizedCaseInsensitiveContains(searchText) ||
                           (item.folder?.name.localizedCaseInsensitiveContains(searchText) ?? false)
                case .folderName:
                    return item.folder?.name.localizedCaseInsensitiveContains(searchText) ?? false
                case .memo:
                    return item.memo.localizedCaseInsensitiveContains(searchText)
                }
            }
        }

        if let start = startDate {
            items = items.filter { $0.capturedAt >= start }
        }
        if let end = endDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
            items = items.filter { $0.capturedAt < endOfDay }
        }

        return items
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dateFilterSection

                if searchText.isEmpty && recentSearches.isEmpty {
                    emptySearchPrompt
                } else if searchText.isEmpty {
                    recentSearchesList
                } else if filteredItems.isEmpty {
                    emptyResultsView
                } else {
                    SearchResultsView(items: filteredItems)
                }
            }
            .navigationTitle("검색")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "폴더명, 메모 검색")
            .searchScopes($searchScope) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty { return }
            }
            .onSubmit(of: .search) {
                saveRecentSearch(searchText)
            }
            .onAppear {
                loadRecentSearches()
            }
        }
    }

    @ViewBuilder
    private var dateFilterSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation { showDateFilter.toggle() }
            } label: {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text("날짜 범위 필터")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if startDate != nil || endDate != nil {
                        Text("적용됨")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Image(systemName: showDateFilter ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            if showDateFilter {
                VStack(spacing: 12) {
                    HStack {
                        Text("시작일")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { startDate ?? Date() },
                                set: { startDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        if startDate != nil {
                            Button("지우기") { startDate = nil }
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Spacer()
                    }
                    HStack {
                        Text("종료일")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { endDate ?? Date() },
                                set: { endDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        if endDate != nil {
                            Button("지우기") { endDate = nil }
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var emptySearchPrompt: some View {
        ContentUnavailableView(
            "검색어를 입력하세요",
            systemImage: "magnifyingglass",
            description: Text("폴더명이나 메모로 미디어를 검색할 수 있습니다.")
        )
    }

    private var emptyResultsView: some View {
        ContentUnavailableView.search(text: searchText)
    }

    private var recentSearchesList: some View {
        List {
            Section("최근 검색") {
                ForEach(recentSearches, id: \.self) { term in
                    Button {
                        searchText = term
                    } label: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                            Text(term)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .onDelete { indexSet in
                    recentSearches.remove(atOffsets: indexSet)
                    saveRecentSearches()
                }
            }
        }
    }

    private func saveRecentSearch(_ term: String) {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        recentSearches.removeAll { $0 == term }
        recentSearches.insert(term, at: 0)
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }
        saveRecentSearches()
    }

    private func saveRecentSearches() {
        recentSearchesData = (try? JSONEncoder().encode(recentSearches)) ?? Data()
    }

    private func loadRecentSearches() {
        recentSearches = (try? JSONDecoder().decode([String].self, from: recentSearchesData)) ?? []
    }
}

enum SearchScope: String, CaseIterable, Identifiable {
    case all, folderName, memo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "전체"
        case .folderName: return "폴더명"
        case .memo: return "메모"
        }
    }
}
