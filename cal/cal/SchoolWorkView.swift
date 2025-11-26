import SwiftUI
import UniformTypeIdentifiers
import Combine

struct SchoolWorkView: View {
    var showNavigationTitle: Bool = true
    private static let defaultFeedURL = ""
    private let parser = CanvasICSParser()
    @EnvironmentObject private var data: AppData
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var errorMessage: String?
    @State private var isImporterPresented = false
    @State private var isURLImportPresented = false
    @State private var urlDraft = URLImportDraft(urlString: SchoolWorkView.defaultFeedURL)
    @State private var isDownloadingFromURL = false
    @State private var hasPreparedSampleFile = false
    @State private var isSyncingAssignments = false
    @State private var now: Date = Date()
    @State private var activeAssignmentRoute: AssignmentRoute?

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let syncFallbackMessage = "Loaded saved data due to network error."

    private var formattedLastUpdated: String? {
        guard let lastUpdated = data.assignmentsLastUpdated else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: lastUpdated)
    }

    var body: some View {
        NavigationStack {
            assignmentListContent
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSyncingAssignments {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Button {
                            syncAssignments()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(!canSyncAssignments)
                        .accessibilityLabel("Sync")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            urlDraft = URLImportDraft(urlString: SchoolWorkView.defaultFeedURL)
                            errorMessage = nil
                            isURLImportPresented = true
                        } label: {
                            Label("Import from URL", systemImage: "link")
                        }

                        Button {
                            errorMessage = nil
                            prepareSampleFileIfNeeded()
                            isImporterPresented = true
                        } label: {
                            Label("Import from file", systemImage: "tray.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import Canvas ICS")
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importAssignments(from: url)
                case .failure(let error):
                    errorMessage = "Failed to import file: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $isURLImportPresented) {
                URLImportSheet(
                    draft: $urlDraft,
                    isLoading: $isDownloadingFromURL
                ) { urlString in
                    Task {
                        await importAssignments(fromURLString: urlString)
                    }
                }
                .presentationDetents([.medium])
            }
            .onAppear {
                now = Date()
                prepareSampleFileIfNeeded()
            }
            .onReceive(timer) { output in
                now = output
            }
            .navigationDestination(item: $activeAssignmentRoute) { route in
                AssignmentDetailView(assignmentID: route.id)
        }
    }
    }

    @ViewBuilder
    private var assignmentListContent: some View {
        if data.assignments.isEmpty && errorMessage == nil {
            ContentUnavailableView(
                "Load Canvas assignments",
                systemImage: "tray.and.arrow.down",
                description: Text("Tap the top-right button to import an ICS file from Canvas and populate the assignment list.")
            )
        } else {
            List {
                lastUpdatedSection
                assignmentSectionsView
                errorSection
            }
            .listStyle(.insetGrouped)
        }
    }

    private var canSyncAssignments: Bool {
        data.lastAssignmentSync != nil
    }

    @ViewBuilder
    private var lastUpdatedSection: some View {
        if let formattedLastUpdated {
            Section {
                Label("Last sync: \(formattedLastUpdated)", systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var assignmentSectionsView: some View {
        ForEach(assignmentSections) { section in
            Section(section.title) {
                ForEach(section.assignments) { assignment in
                    AssignmentRow(
                        assignment: assignment,
                        now: now,
                        onToggleCompletion: {
                            data.toggleAssignmentCompletion(id: assignment.id)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        activeAssignmentRoute = AssignmentRoute(id: assignment.id)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        completionSwipeAction(for: assignment)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            Section("Error") {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func completionSwipeAction(for assignment: SchoolAssignment) -> some View {
        Button {
            data.toggleAssignmentCompletion(id: assignment.id)
        } label: {
            Text(assignment.isCompleted ? "Mark incomplete" : "Mark complete")
        }
        .tint(assignment.isCompleted ? .orange : .green)
    }

    private var allowedContentTypes: [UTType] {
        var types: [UTType] = []
        if let icsType = UTType(filenameExtension: "ics") {
            types.append(icsType)
        }
        if #available(iOS 14.0, *) {
            types.append(.calendarEvent)
        }
        if types.isEmpty {
            types.append(.data)
        }
        return types
    }

    private func importAssignments(from url: URL) {
        do {
            let icsData = try Data(contentsOf: url)
            let syncSource = AssignmentSyncSource(
                kind: .file,
                remoteURLString: nil,
                displayName: url.lastPathComponent.isEmpty ? "파일" : url.lastPathComponent
            )
            try applyAssignments(from: icsData, syncSource: syncSource)
            errorMessage = nil
        } catch {
            handleImportError(error)
        }
    }

    @MainActor
    private func importAssignments(fromURLString urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            errorMessage = "유효한 URL을 입력해주세요."
            return
        }

        isDownloadingFromURL = true

        do {
            let (icsData, _) = try await URLSession.shared.data(from: url)
            let syncSource = AssignmentSyncSource(
                kind: .url,
                remoteURLString: trimmed,
                displayName: url.host ?? trimmed
            )
            try applyAssignments(from: icsData, syncSource: syncSource)
            isURLImportPresented = false
            errorMessage = nil
        } catch {
            handleImportError(error)
        }

        isDownloadingFromURL = false
    }

    private func applyAssignments(from icsData: Data, syncSource: AssignmentSyncSource) throws {
        let parsedAssignments = try parser.parseAssignments(from: icsData)
        self.data.replaceAssignments(with: parsedAssignments, syncSource: syncSource, rawICSData: icsData)
    }

    private func syncAssignments() {
        guard !isSyncingAssignments else { return }
        guard let syncSource = data.lastAssignmentSync else {
            errorMessage = "동기화할 수 있는 기록이 없어요."
            return
        }

        isSyncingAssignments = true

        Task {
            do {
                let (icsData, usedFallback) = try await fetchICSData(for: syncSource)
                try await MainActor.run {
                    try applyAssignments(from: icsData, syncSource: syncSource)
                    errorMessage = usedFallback ? syncFallbackMessage : nil
                }
            } catch {
                await MainActor.run {
                    handleImportError(error)
                }
            }

            await MainActor.run {
                isSyncingAssignments = false
            }
        }
    }

    private func fetchICSData(for source: AssignmentSyncSource) async throws -> (Data, Bool) {
        switch source.kind {
        case .file:
            if let stored = data.loadStoredAssignmentsICSData() {
                return (stored, false)
            }
            throw AssignmentSyncError.localFileMissing

        case .url:
            guard let urlString = source.remoteURLString,
                  let remoteURL = URL(string: urlString) else {
                throw AssignmentSyncError.invalidURL
            }

            do {
                let (icsData, _) = try await URLSession.shared.data(from: remoteURL)
                return (icsData, false)
            } catch {
                if let stored = data.loadStoredAssignmentsICSData() {
                    return (stored, true)
                }
                throw error
            }
        }
    }

    private func handleImportError(_ error: Error) {
        if let syncError = error as? AssignmentSyncError {
            errorMessage = syncError.localizedDescription
            return
        }

        if let parserError = error as? CanvasICSParser.ParserError {
            switch parserError {
            case .invalidData:
                errorMessage = "파일을 읽을 수 없어요. 다른 파일로 시도해보세요."
            case .noEvents:
                errorMessage = "파일에서 과제 정보를 찾지 못했어요."
            }
        } else if (error as NSError).domain == NSURLErrorDomain {
            errorMessage = "URL에서 데이터를 가져오지 못했어요. 네트워크 상태와 주소를 확인해주세요."
        } else {
            errorMessage = "알 수 없는 오류가 발생했어요: \(error.localizedDescription)"
        }
    }

    private var assignmentSections: [AssignmentSection] {
        let grouped = Dictionary(grouping: data.assignments) { assignment in
            calendar.startOfDay(for: assignment.dueDate)
        }

        let sortedKeys = grouped.keys.sorted()

        return sortedKeys.map { date in
            let assignmentsForDate = grouped[date] ?? []
            let sortedAssignments = assignmentsForDate.sorted { lhs, rhs in
                if lhs.isCompleted == rhs.isCompleted {
                    return lhs.dueDate < rhs.dueDate
                }
                return !lhs.isCompleted && rhs.isCompleted
            }
            let title = sectionTitleFormatter.string(from: date)

            return AssignmentSection(
                id: date,
                title: title,
                assignments: sortedAssignments
            )
        }
    }

    private var sectionTitleFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter
    }

    private func prepareSampleFileIfNeeded() {
        guard !hasPreparedSampleFile else { return }
        hasPreparedSampleFile = true
        SampleICSSupport.shared.ensureSampleFileAvailable()
    }
}

struct AssignmentRow: View {
    let assignment: SchoolAssignment
    let now: Date
    let onToggleCompletion: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    private var isLate: Bool {
        guard !assignment.isCompleted else { return false }
        let latestDue = assignment.displayEndDate(using: calendar) ?? assignment.dueDate
        return latestDue < now
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleCompletion) {
                Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(assignment.isCompleted ? Color.green : Color.secondary)
                    .accessibilityLabel(assignment.isCompleted ? "과제 완료 취소" : "과제 완료")
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(assignment.title)
                    .font(.headline)
                    .strikethrough(assignment.isCompleted, color: .primary)
                    .opacity(assignment.isCompleted ? 0.6 : 1)

                Label(dueSummary, systemImage: assignment.isAllDay ? "calendar" : "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(isLate ? Color.red : Color.secondary)

                if let minutes = assignment.estimatedDurationMinutes, minutes > 0 {
                    Label(durationText(for: minutes), systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let course = assignment.course {
                    Label(course, systemImage: "graduationcap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let location = assignment.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let description = descriptionPreview {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if isLate {
                    Text("늦음")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else if assignment.isCompleted {
                    Text("완료됨")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .opacity(assignment.isCompleted ? 0.7 : 1)
    }

    private var dueSummary: String {
        if assignment.isAllDay {
            guard let end = assignment.displayEndDate(using: calendar) else {
                return formattedDateOnly(assignment.dueDate)
            }
            let startText = formattedDateOnly(assignment.dueDate)
            if calendar.isDate(assignment.dueDate, inSameDayAs: end) {
                if assignment.usesFallbackEnd {
                    return "\(startText) · 23:59 종료"
                }
                return "\(startText) · \(formattedTime(end)) 종료"
            }
            let endText = formattedDateOnly(end)
            if assignment.usesFallbackEnd {
                return "\(startText) ~ \(endText) · \(formattedTime(end)) 종료"
            }
            return "\(startText) ~ \(endText)"
        }

        if let endDate = assignment.endDate {
            if calendar.isDate(assignment.dueDate, inSameDayAs: endDate) {
                return "\(formattedDateTime(assignment.dueDate)) - \(formattedTime(endDate))"
            }
            return "\(formattedDateTime(assignment.dueDate)) ~ \(formattedDateTime(endDate))"
        }

        return formattedDateTime(assignment.dueDate)
    }

    private var descriptionPreview: String? {
        guard let text = assignment.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private func durationText(for minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        if hours > 0 && remaining > 0 {
            return "\(hours)시간 \(remaining)분 예상"
        } else if hours > 0 {
            return "\(hours)시간 예상"
        }
        return "\(remaining)분 예상"
    }

    private func formattedDateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct AssignmentDetailView: View {
    let assignmentID: String

    @EnvironmentObject private var data: AppData
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var now: Date = Date()
    @State private var isPresentingSegmentSheet = false
    @State private var segmentDraft = TaskSegmentDraft()
    @State private var editingSegment: TaskSegment?

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var assignment: SchoolAssignment? {
        data.assignments.first(where: { $0.id == assignmentID })
    }

    private var segments: [TaskSegment] {
        data.segments(for: .assignment, parentIdentifier: assignmentID)
    }

    private var isLate: Bool {
        guard let assignment else { return false }
        let deadline = assignment.displayEndDate(using: calendar) ?? assignment.dueDate
        return !assignment.isCompleted && deadline < now
    }

    var body: some View {
        Group {
            if let assignment {
                List {
                    Section {
                        Text(assignment.title)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button(assignment.isCompleted ? "완료 취소" : "완료 표시") {
                                data.toggleAssignmentCompletion(id: assignment.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(assignment.isCompleted ? .orange : .green)

                            if isLate {
                                Text("Late")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                        }

                        if let course = assignment.course {
                            Label(course, systemImage: "graduationcap")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let location = assignment.location {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("일정") {
                        if assignment.isAllDay {
                            detailRow(title: "시작", value: dateOnlyFormatter.string(from: assignment.dueDate))
                            if let endInfo = allDayEndDisplay(for: assignment) {
                                detailRow(title: endInfo.title, value: endInfo.value)
                            }
                        } else {
                            let startTitle = assignment.endDate != nil ? "시작" : "일시"
                            detailRow(title: startTitle, value: dateTimeFormatter.string(from: assignment.dueDate))
                            if let endDate = assignment.endDate {
                                detailRow(title: "종료", value: dateTimeFormatter.string(from: endDate))
                            }
                        }
                    }

                    Section("예상 소요 시간") {
                        Picker("소요 시간", selection: assignmentDurationBinding) {
                            Text("선택 안 함").tag(0)
                            ForEach(durationOptions.filter { $0 > 0 }, id: \.self) { minutes in
                                Text(durationLabel(for: minutes)).tag(minutes)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }

                    if let url = assignment.url {
                        Section("링크") {
                            Link("Canvas에서 열기", destination: url)
                                .font(.body.weight(.semibold))
                        }
                    }

                    if let description = fullDescription(for: assignment) {
                        Section("설명") {
                            Text(description)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    segmentSection(for: assignment)
                }
                .listStyle(.insetGrouped)
                .navigationTitle("상세 보기")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $isPresentingSegmentSheet) {
                    TaskSegmentEditorSheet(
                        mode: editingSegment == nil ? .create : .edit,
                        draft: $segmentDraft,
                        parentName: assignment.title
                    ) { draft in
                        if let existing = editingSegment {
                            var updated = existing
                            updated.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                            updated.dueDate = draft.dueDate
                            updated.startDate = draft.startDate
                            updated.hasDeadline = draft.hasDeadline
                            updated.priority = draft.priority
                            updated.estimatedDurationMinutes = draft.estimatedDurationMinutes
                            data.update(segment: updated)
                        } else {
                            let newSegment = TaskSegment(
                                parentType: .assignment,
                                parentIdentifier: assignment.id,
                                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                dueDate: draft.dueDate,
                                startDate: draft.startDate,
                                hasDeadline: draft.hasDeadline,
                                priority: draft.priority,
                                estimatedDurationMinutes: draft.estimatedDurationMinutes
                            )
                            data.add(segment: newSegment)
                        }
                        editingSegment = nil
                    }
                }
            } else {
                ContentUnavailableView(
                    "과제를 찾을 수 없어요",
                    systemImage: "questionmark.circle",
                    description: Text("다시 로드하거나 목록에서 다른 과제를 선택해보세요.")
                )
            }
        }
        .onAppear { now = Date() }
        .onReceive(timer) { now = $0 }
    }

    private func fullDescription(for assignment: SchoolAssignment) -> String? {
        guard let text = assignment.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private func allDayEndDisplay(for assignment: SchoolAssignment) -> (title: String, value: String)? {
        guard let endDate = assignment.displayEndDate(using: calendar) else {
            return nil
        }

        let title = assignment.usesFallbackEnd ? "종료 (기본 23:59)" : "종료"
        let value = dateTimeFormatter.string(from: endDate)
        return (title, value)
    }

    private var durationOptions: [Int] {
        Array(stride(from: 0, through: 8 * 60, by: 30))
    }

    private var assignmentDurationBinding: Binding<Int> {
        Binding(
            get: { data.assignments.first(where: { $0.id == assignmentID })?.estimatedDurationMinutes ?? 0 },
            set: { newValue in
                let minutes = newValue == 0 ? nil : newValue
                data.setAssignmentDuration(id: assignmentID, minutes: minutes)
            }
        )
    }

    private func durationLabel(for minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        if hours > 0 && remaining > 0 {
            return "\(hours)시간 \(remaining)분"
        } else if hours > 0 {
            return "\(hours)시간"
        }
        return "\(remaining)분"
    }

    @ViewBuilder
    private func segmentSection(for assignment: SchoolAssignment) -> some View {
        Section("세부 단계") {
            if segments.isEmpty {
                Text("세부 단계가 없습니다. 아래 버튼으로 추가하세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(segments) { segment in
                    TaskSegmentRow(
                        segment: segment,
                        onToggleCompletion: {
                            data.toggleSegmentCompletion(id: segment.id)
                        },
                        onStart: {
                            data.startSegmentProgress(id: segment.id)
                        },
                        onPause: {
                            data.pauseSegmentProgress(id: segment.id)
                        },
                        onFinish: {
                            data.completeSegmentProgress(id: segment.id)
                        },
                        onEdit: {
                            segmentDraft = TaskSegmentDraft(segment: segment)
                            editingSegment = segment
                            isPresentingSegmentSheet = true
                        }
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            data.removeSegment(id: segment.id)
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            segmentDraft = TaskSegmentDraft(segment: segment)
                            editingSegment = segment
                            isPresentingSegmentSheet = true
                        } label: {
                            Label("편집", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }

            Button {
                segmentDraft = TaskSegmentDraft()
                segmentDraft.dueDate = assignment.dueDate
                segmentDraft.hasDeadline = !assignment.isAllDay
                segmentDraft.startDate = assignment.isAllDay ? nil : assignment.dueDate
                isPresentingSegmentSheet = true
                editingSegment = nil
            } label: {
                Label("단계 추가", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }

    private var dateOnlyFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }

    private var dateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }
}

private struct URLImportSheet: View {
    @Binding var draft: URLImportDraft
    @Binding var isLoading: Bool
    var onImport: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("URL 입력") {
                    TextField("https://", text: $draft.urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("URL에서 가져오기")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("가져오기") {
                        onImport(draft.urlString)
                    }
                    .disabled(!draft.isValid || isLoading)
                }
            }
        }
    }
}

private struct URLImportDraft {
    var urlString: String = ""

    var isValid: Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}

private struct AssignmentSection: Identifiable {
    let id: Date
    let title: String
    let assignments: [SchoolAssignment]
}

private struct AssignmentRoute: Identifiable, Hashable {
    let id: String
}

private enum AssignmentSyncError: LocalizedError {
    case localFileMissing
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .localFileMissing:
            return "저장된 파일을 찾을 수 없어요. 파일을 다시 가져와주세요."
        case .invalidURL:
            return "저장된 URL이 올바르지 않아요. 다시 URL을 입력해주세요."
        }
    }
}

#Preview {
    NavigationStack {
        SchoolWorkView()
    }
    .environmentObject(AppData())
}
