import Foundation
import SwiftUI

struct ScheduleChatView: View {
    @AppStorage("openAIAPIKey") private var apiKey: String = ""
    @EnvironmentObject private var data: AppData
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var messages: [ChatMessage] = []
    @State private var draft: String = ""
    @State private var isPresentingAPIKeySheet = false
    @State private var isSending = false

    private let assistant = ScheduleAssistant()
    private let chatService = OpenAIChatService()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
                .onChange(of: messages) { _, _ in
                    if let last = messages.last {
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Type a message", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit {
                        sendMessage()
                    }
                    .disabled(isSending)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    .navigationTitle("Schedule Chat")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isPresentingAPIKeySheet = true
                } label: {
                    Image(systemName: apiKey.isEmpty ? "key.slash" : "key.fill")
                }
                .accessibilityLabel("OpenAI API Key settings")
            }
        }
        .sheet(isPresented: $isPresentingAPIKeySheet) {
            APIKeyEntrySheet(apiKey: $apiKey)
                .presentationDetents([.medium])
        }
        .onAppear {
                if messages.isEmpty {
                var intro = assistant.greeting
                if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    intro += "\n\nIf you set an OpenAI API key, ChatGPT can converse and help manage your schedule. Tap the key icon in the top-right to save the key."
                }
                messages.append(ChatMessage(role: .assistant, text: intro))
            }
        }
    }

    @MainActor
    private func sendMessage() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        draft = ""

        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let reply = assistant.fallbackResponse(
                to: trimmed,
                data: data,
                calendar: calendar,
                locale: locale
            )
            messages.append(ChatMessage(role: .assistant, text: reply))
            return
        }

        let history = messages
    let placeholder = ChatMessage(role: .assistant, text: "OpenAI is preparing a response...")
        messages.append(placeholder)
        isSending = true

        Task {
            do {
                let requestMessages = assistant.makeRequestMessages(
                    for: history,
                    data: data,
                    calendar: calendar,
                    locale: locale
                )
                let replyText = try await chatService.send(messages: requestMessages, apiKey: apiKey)
                await MainActor.run {
                    let processed = assistant.process(
                        replyText,
                        data: data,
                        calendar: calendar,
                        locale: locale
                    )
                    replaceMessage(id: placeholder.id, with: processed.text)
                    for summary in processed.actionSummaries {
                        messages.append(ChatMessage(role: .assistant, text: summary))
                    }
                }
            } catch {
                await MainActor.run {
                    replaceMessage(id: placeholder.id, with: "An error occurred while requesting OpenAI: \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                isSending = false
            }
        }
    }

    @MainActor
    private func replaceMessage(id: UUID, with newText: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            let message = messages[index]
            messages[index] = ChatMessage(role: message.role, text: newText, timestamp: message.timestamp)
        }
    }
}

private struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date

    init(role: Role, text: String, timestamp: Date = Date()) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

extension ChatMessage: Equatable {
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
    }

    private var bubble: some View {
        Text(message.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(message.role == .assistant ? Color(.secondarySystemBackground) : Color.accentColor.opacity(0.85))
            .foregroundColor(message.role == .assistant ? .primary : .white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct APIKeyEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var apiKey: String
    @State private var draft: String

    init(apiKey: Binding<String>) {
        _apiKey = apiKey
        _draft = State(initialValue: apiKey.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI API Key") {
                    SecureField("sk-...", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("The key is stored only on this device. Get an API key from the OpenAI dashboard.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("API Key Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        apiKey = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ScheduleAssistant {
    private struct ActionExtractionResult {
        let envelope: AssistantActionEnvelope?
        let sanitizedReply: String
        let parseErrorDescription: String?
    }

    private let instructions = """
    Hi — I'm your schedule assistant. Use the commands below to manage your schedule:
    - `todo list` : Show registered todos.
    - `todo today` : Show todos due today.
    - `todo add Title | 2024-08-01 09:00 | high | 90` : Add a new todo (duration in minutes optional).
    - `todo complete 1` : Mark a todo complete by list number or partial title.
    - `assignment list` : Show Canvas assignments.
    - `routine list` : Show registered routines.
    Type `help` anytime to see these instructions again.

    If you connect an OpenAI API key, ChatGPT can use the same data to converse naturally and assist with scheduling. If an action is needed, ChatGPT will include a `<schedule_actions>...</schedule_actions>` block containing a JSON object with the requested changes.
    """

    var greeting: String { instructions }

    @MainActor
    func fallbackResponse(to rawInput: String, data: AppData, calendar: Calendar, locale: Locale) -> String {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "How can I help?"
        }

        let lowercased = trimmed.lowercased()

        if containsKeyword(in: lowercased, keywords: ["help"]) {
            return instructions
        }

        if isTodayTodoCommand(lowercased) {
            return formatTodos(
                data.todos.filter { calendar.isDate($0.dueDate, inSameDayAs: Date()) },
                calendar: calendar,
                locale: locale,
                emptyText: "No todos due today."
            )
        }

        if let response = handleTodoCompletionCommand(trimmed, lowercased: lowercased, data: data) {
            return response
        }

        if let response = handleTodoAdditionCommand(trimmed, lowercased: lowercased, data: data, calendar: calendar, locale: locale) {
            return response
        }

        if isTodoListCommand(lowercased) {
            return formatTodos(data.todos, calendar: calendar, locale: locale)
        }

        if isAssignmentListCommand(lowercased) {
            return formatAssignments(data.assignments, calendar: calendar, locale: locale)
        }

        if isRoutineListCommand(lowercased) {
            return formatRoutines(data.routines, calendar: calendar, locale: locale)
        }

        return "I didn't understand that request. Type `help` to see available commands."
    }

    func makeRequestMessages(for history: [ChatMessage], data: AppData, calendar: Calendar, locale: Locale) -> [ChatRequestMessage] {
        let limited = Array(history.suffix(12))
        var messages: [ChatRequestMessage] = []
        messages.append(ChatRequestMessage(role: .system, content: systemPrompt(data: data, calendar: calendar, locale: locale)))
        for message in limited {
            let role: ChatRequestMessage.Role = message.role == .assistant ? .assistant : .user
            messages.append(ChatRequestMessage(role: role, content: message.text))
        }
        return messages
    }

    @MainActor
    func process(_ reply: String, data: AppData, calendar: Calendar, locale: Locale) -> (text: String, actionSummaries: [String]) {
        if let extraction = extractActionEnvelope(from: reply) {
            let primary = (extraction.envelope?.reply ?? extraction.sanitizedReply).trimmingCharacters(in: .whitespacesAndNewlines)
            let safePrimary = primary.isEmpty ? extraction.sanitizedReply : primary
            let displayText = safePrimary.trimmingCharacters(in: .whitespacesAndNewlines)

            if let envelope = extraction.envelope {
                let results = apply(actions: envelope.actions ?? [], data: data, calendar: calendar, locale: locale)
                return (displayText.isEmpty ? "Response was empty." : displayText, results)
            } else {
                let warning = extraction.parseErrorDescription ?? "The schedule_actions block sent by OpenAI could not be parsed."
                return (displayText.isEmpty ? "Response was empty." : displayText, ["⚠️ \(warning)"])
            }
        }

        let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Response was empty." : cleaned, [])
    }

    private func containsKeyword(in text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private func isTodoListCommand(_ text: String) -> Bool {
        containsKeyword(in: text, keywords: ["todo", "할일", "할 일", "tasks"]) &&
        containsKeyword(in: text, keywords: ["list", "show", "보여", "알려", "무슨", "어떤"])
    }

    private func isTodayTodoCommand(_ text: String) -> Bool {
        isTodoListCommand(text) && containsKeyword(in: text, keywords: ["today", "오늘"])
    }

    private func isAssignmentListCommand(_ text: String) -> Bool {
        containsKeyword(in: text, keywords: ["assignment", "과제", "canvas"]) &&
        containsKeyword(in: text, keywords: ["list", "show", "보여", "알려"])
    }

    private func isRoutineListCommand(_ text: String) -> Bool {
        containsKeyword(in: text, keywords: ["routine", "루틴"]) &&
        containsKeyword(in: text, keywords: ["list", "show", "보여", "알려"])
    }

    private func systemPrompt(data: AppData, calendar: Calendar, locale: Locale) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = isoFormatter.string(from: Date())

        let snapshot = scheduleSnapshot(data: data, calendar: calendar, locale: locale)

                return """
                You are "SimpleCalendar Assistant", a helpful scheduling assistant embedded inside an iOS app. Current date-time: \(now) (\(calendar.timeZone.identifier)).

                Instructions:
                1. Prefer responding in English unless the user explicitly requests another language.
                2. If a schedule change is required, include a single `<schedule_actions>...</schedule_actions>` block containing a pure JSON object describing the requested changes. Allowed fields:
                     {
                         "reply": "<optional message to show to the user>",
                         "actions": [
                             {
                                 "type": "todo.add" | "todo.toggle" | "assignment.setDuration",
                                 "title": "<when applicable>",
                                 "dueDate": "<ISO8601 datetime>",
                                 "startDate": "<ISO8601 datetime (optional)>",
                                 "priority": "low" | "medium" | "high",
                                 "identifier": "<UUID or partial title>",
                                 "durationMinutes": <minutes, multiples of 30 (optional)>
                             }
                         ]
                     }
                     Examples:
                     <schedule_actions>{"reply":"Added the todo.","actions":[{"type":"todo.add","title":"Math homework","dueDate":"2025-10-15T00:00:00Z","startDate":"2025-10-14T22:30:00Z","priority":"medium","durationMinutes":90}]}</schedule_actions>
                     <schedule_actions>{"actions":[{"type":"assignment.setDuration","identifier":"Math homework","durationMinutes":120}]}</schedule_actions>
                     - The JSON must not contain comments, missing commas, or mismatched quotes.
                     - Each object in the `actions` array must include a `type`.
                3. If no change is required, omit the `<schedule_actions>` block entirely.
                4. If you disagree with the user's instruction or detect a safety issue, explain why and propose alternatives.
                5. When the user supplies a specific meeting or start time (“meet at 5 PM”, “시작 17시”), treat that time as the `dueDate`. If the user also specifies prep or travel duration, set `startDate` to the earlier time and keep `durationMinutes` for the actual activity.

                The following is the current schedule snapshot:
                \(snapshot)
                """
    }

    private func scheduleSnapshot(data: AppData, calendar: Calendar, locale: Locale) -> String {
        let todos = formatTodos(data.todos, calendar: calendar, locale: locale, limit: 10)
        let assignments = formatAssignments(data.assignments, calendar: calendar, locale: locale, limit: 10)
        let routines = formatRoutines(data.routines, calendar: calendar, locale: locale, limit: 10)

    return """
    [Todos]
    \(todos)

    [Assignments]
    \(assignments)

    [Routines]
    \(routines)
    """
    }

    private func extractActionEnvelope(from reply: String) -> ActionExtractionResult? {
        guard let start = reply.range(of: "<schedule_actions>"),
              let end = reply.range(of: "</schedule_actions>", range: start.upperBound..<reply.endIndex) else {
            return nil
        }

        let rawContent = reply[start.upperBound..<end.lowerBound]
        let before = reply[..<start.lowerBound]
        let after = reply[end.upperBound...]
        let sanitized = (before + after).trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)

        let decoder = JSONDecoder()
        let candidates: [String] = {
            var base = [trimmed]
            let compact = trimmed
            if !compact.hasPrefix("{") && !compact.hasPrefix("[") {
                base.append("{" + compact + "}")
            }
            return base
        }()

        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let envelope = try? decoder.decode(AssistantActionEnvelope.self, from: data) {
                return ActionExtractionResult(envelope: envelope, sanitizedReply: sanitized, parseErrorDescription: nil)
            }
        }

        if let fallback = parseLooseActionEnvelope(from: trimmed) {
            return ActionExtractionResult(envelope: fallback, sanitizedReply: sanitized, parseErrorDescription: nil)
        }

        return ActionExtractionResult(envelope: nil, sanitizedReply: sanitized, parseErrorDescription: "OpenAI가 보낸 schedule_actions 블록이 올바른 JSON 형식이 아니라서 작업을 실행하지 못했어요.")
    }

    private func parseLooseActionEnvelope(from raw: String) -> AssistantActionEnvelope? {
        let normalized = collapseWhitespace(in: raw)
        guard !normalized.isEmpty else { return nil }

        let reply = captureValue(for: "reply", in: normalized)
        var actionType = captureValue(for: "type", in: normalized)
        let title = captureValue(for: "title", in: normalized)
        let dueDate = captureValue(for: "dueDate", in: normalized) ?? captureValue(for: "due_date", in: normalized)
        let startDate = captureValue(for: "startDate", in: normalized) ?? captureValue(for: "start_date", in: normalized)
        let priority = captureValue(for: "priority", in: normalized)
        let identifier = captureValue(for: "identifier", in: normalized)
        let durationString = captureValue(for: "durationMinutes", in: normalized)
            ?? captureValue(for: "duration_minutes", in: normalized)
            ?? captureValue(for: "duration", in: normalized)
        let duration = durationString.flatMap(parseDurationMinutes)

        if actionType == nil {
            if title != nil || dueDate != nil || priority != nil || duration != nil {
                actionType = "todo.add"
            } else if identifier != nil && duration != nil {
                actionType = "assignment.setDuration"
            }
        }

        guard let determinedType = actionType else {
            return nil
        }

        let payload = AssistantActionPayload(
            type: determinedType,
            title: title,
            dueDate: dueDate,
            startDate: startDate,
            priority: priority,
            identifier: identifier,
            durationMinutes: duration
        )

        return AssistantActionEnvelope(reply: reply, actions: [payload])
    }

    private func captureValue(for key: String, in text: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            "\"\(escapedKey)\"\\s*:\\s*\"([^\"]+)\"",
            "\"\(escapedKey)\"\\s*:\\s*'([^']+)'",
            "\(escapedKey)\\s*:\\s*\"([^\"]+)\""
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               match.numberOfRanges > 1,
               let valueRange = Range(match.range(at: 1), in: text) {
                return String(text[valueRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
        }

        return nil
    }

    private func collapseWhitespace(in text: String) -> String {
        let components = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }

    private func shouldTreatAsLocal(_ original: String) -> Bool {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("Z") || trimmed.hasSuffix("z") {
            return true
        }
        if let range = trimmed.range(of: #"([+-]\d{2}:\d{2})$"#, options: .regularExpression) {
            let suffix = String(trimmed[range])
            return suffix == "+00:00" || suffix == "-00:00"
        }
        return false
    }

    private func adjustToLocal(_ date: Date, calendar: Calendar) -> Date {
        let offset = calendar.timeZone.secondsFromGMT(for: date)
        return date.addingTimeInterval(TimeInterval(-offset))
    }

    private func parseAsLocal(_ text: String, calendar: Calendar, locale: Locale) -> Date? {
        let cleaned = text
            .replacingOccurrences(of: "Z", with: "")
            .replacingOccurrences(of: "z", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd"
        ]

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return date
            }
        }

        return nil
    }

    private func indicatesMidnight(in text: String) -> Bool {
        let lowered = text.lowercased()

        if lowered.contains("자정") || lowered.contains("midnight") {
            return true
        }

        if lowered.contains("t00:00") || lowered.contains(" 00:00") {
            return true
        }

        if let match = lowered.range(of: #"00:00(:00(\.0+)?)?$"#, options: [.regularExpression]) {
            return !match.isEmpty
        }

        return false
    }

    private func finalize(date: Date, isMidnight: Bool, calendar: Calendar) -> Date {
        guard isMidnight else { return date }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let base = calendar.date(from: components),
              let adjusted = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: base) else {
            return date
        }
        return adjusted
    }

    @MainActor
    private func apply(actions: [AssistantActionPayload], data: AppData, calendar: Calendar, locale: Locale) -> [String] {
        var results: [String] = []

        for action in actions {
            switch action.type.lowercased() {
            case "todo.add":
                guard let title = action.title, let rawDueDate = action.dueDate else { continue }
                guard let dueDate = parseActionDate(rawDueDate, calendar: calendar, locale: locale) else { continue }
                let resolvedStart = action.startDate.flatMap { parseActionDate($0, calendar: calendar, locale: locale) }
                let priorityText = action.priority?.lowercased() ?? "medium"
                let priority = TaskPriority(rawValue: priorityText) ?? mapPriority(priorityText) ?? .medium
                let duration = sanitizedDurationMinutes(action.durationMinutes)
                let computedStart: Date?
                if let resolvedStart {
                    computedStart = resolvedStart
                } else if let duration {
                    computedStart = dueDate.addingTimeInterval(-TimeInterval(duration * 60))
                } else {
                    computedStart = nil
                }
                let newTask = TaskItem(
                    title: title,
                    dueDate: dueDate,
                    startDate: computedStart,
                    priority: priority,
                    estimatedDurationMinutes: duration
                )
                data.add(task: newTask)
                let durationNote = duration.map { " (est. \(durationSummary(for: $0)))" } ?? ""
                let startNote = computedStart.map { " starting \(formatted(date: $0, locale: locale))" } ?? ""
                results.append("🆕 \"\(title)\" added with due \(formatted(date: dueDate, locale: locale))\(startNote)\(durationNote).")

            case "todo.toggle", "todo.complete":
                guard let identifier = action.identifier ?? action.title else { continue }
                guard let target = locateTodoByIdentifier(in: data.todos, identifier: identifier) else { continue }
                data.toggleTaskCompletion(id: target.id)
                let status = target.isCompleted ? "incomplete" : "completed"
                results.append("🔄 Toggled todo \"\(target.title)\" to \(status).")

            case "assignment.setduration", "assignment.duration", "assignment.updateduration":
                guard let identifier = action.identifier ?? action.title else { continue }
                guard let target = locateAssignmentByIdentifier(in: data.assignments, identifier: identifier) else { continue }
                let duration = sanitizedDurationMinutes(action.durationMinutes)
                data.setAssignmentDuration(id: target.id, minutes: duration)
                if let duration {
                    results.append("⏱️ Set estimated duration for \"\(target.title)\" to \(durationSummary(for: duration)).")
                } else {
                    results.append("⏱️ Removed estimated duration for \"\(target.title)\".")
                }

            default:
                continue
            }
        }

        return results
    }

    private func parseActionDate(_ text: String, calendar: Calendar, locale: Locale) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let midnightHint = indicatesMidnight(in: trimmed)

        let formatterWithFraction = ISO8601DateFormatter()
        formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFraction.date(from: trimmed) {
            let resolved = shouldTreatAsLocal(trimmed) ? adjustToLocal(date, calendar: calendar) : date
            return finalize(date: resolved, isMidnight: midnightHint, calendar: calendar)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: trimmed) {
            let resolved = shouldTreatAsLocal(trimmed) ? adjustToLocal(date, calendar: calendar) : date
            return finalize(date: resolved, isMidnight: midnightHint, calendar: calendar)
        }

        if shouldTreatAsLocal(trimmed),
           let localDate = parseAsLocal(trimmed, calendar: calendar, locale: locale) {
            return finalize(date: localDate, isMidnight: midnightHint, calendar: calendar)
        }

        if let fallback = parseDate(trimmed, calendar: calendar, locale: locale) {
            return finalize(date: fallback, isMidnight: midnightHint, calendar: calendar)
        }

        return nil
    }

    private func locateTodoByIdentifier(in todos: [TaskItem], identifier: String) -> TaskItem? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let uuid = UUID(uuidString: trimmed), let match = todos.first(where: { $0.id == uuid }) {
            return match
        }
        if let index = Int(trimmed), todos.indices.contains(index - 1) {
            return todos[index - 1]
        }
        let lowered = trimmed.lowercased()
        return todos.first { $0.title.lowercased().contains(lowered) }
    }

    private func locateAssignmentByIdentifier(in assignments: [SchoolAssignment], identifier: String) -> SchoolAssignment? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let exact = assignments.first(where: { $0.id == trimmed }) {
            return exact
        }

        if let index = Int(trimmed), assignments.indices.contains(index - 1) {
            return assignments[index - 1]
        }

        let lowered = trimmed.lowercased()
        return assignments.first { assignment in
            assignment.title.lowercased().contains(lowered)
                || assignment.course?.lowercased().contains(lowered) == true
        }
    }

    @MainActor
    private func handleTodoCompletionCommand(_ original: String, lowercased: String, data: AppData) -> String? {
        guard containsKeyword(in: lowercased, keywords: ["complete", "완료", "끝", "done"])
        && containsKeyword(in: lowercased, keywords: ["todo", "할일", "할 일", "task"]) else {
            return nil
        }

        guard let target = locateTodo(in: data.todos, from: original) else {
                return "Couldn't find a todo to mark complete. Provide a partial title or list number."
        }

        data.toggleTaskCompletion(id: target.id)
        return "\"\(target.title)\" 할 일의 완료 상태를 토글했어요."
    }

    @MainActor
    private func handleTodoAdditionCommand(_ original: String, lowercased: String, data: AppData, calendar: Calendar, locale: Locale) -> String? {
        guard containsKeyword(in: lowercased, keywords: ["add", "추가"]) &&
              containsKeyword(in: lowercased, keywords: ["todo", "할일", "할 일", "task"]) else {
            return nil
        }

        var payload = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandPrefixes = ["todo add", "할일 추가", "할 일 추가", "task add"]
        for prefix in commandPrefixes {
            if lowercased.hasPrefix(prefix) {
                let offset = prefix.count
                if let start = original.index(original.startIndex, offsetBy: offset, limitedBy: original.endIndex) {
                    payload = String(original[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                break
            }
        }

        let components = payload.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard components.count >= 3 else {
            return "Invalid format. Use: `todo add Title | 2024-08-01 09:00 | high`"
        }

        let title = components[0]
        guard let dueDate = parseDate(String(components[1]), calendar: calendar, locale: locale) else {
            return "Could not parse the date. Use format: `2024-08-01 09:00`"
        }

        let priorityString = components[2].lowercased()
        guard let priority = TaskPriority(rawValue: priorityString) ?? mapPriority(priorityString) else {
            return "Unrecognized priority. Choose from `low`, `medium`, `high`."
        }

        let durationMinutes = components.count >= 4 ? parseDurationMinutes(String(components[3])) : nil
        var startDate = components.count >= 5 ? parseDate(String(components[4]), calendar: calendar, locale: locale) : nil

        let sanitizedDuration = sanitizedDurationMinutes(durationMinutes)
        if startDate == nil, let sanitizedDuration {
            startDate = dueDate.addingTimeInterval(-TimeInterval(sanitizedDuration * 60))
        }

        let newTask = TaskItem(
            title: title,
            dueDate: dueDate,
            startDate: startDate,
            priority: priority,
            estimatedDurationMinutes: sanitizedDuration
        )
        data.add(task: newTask)
        let durationNote = newTask.estimatedDurationMinutes.map { " (예상 \(durationSummary(for: $0)))" } ?? ""
        let startNote = startDate.map { " · 시작 \(formatted(date: $0, locale: locale))" } ?? ""
        return "\"\(title)\" 할 일을 \(formatted(date: dueDate, locale: locale)) 마감으로 추가했어요\(startNote)\(durationNote)."
    }

    private func mapPriority(_ text: String) -> TaskPriority? {
        switch text {
        case "low":
            return .low
        case "medium", "mid", "normal":
            return .medium
        case "high":
            return .high
        default:
            return nil
        }
    }

    private func parseDurationMinutes(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = Int(trimmed) {
            return direct
        }
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        return value
    }

    private func sanitizedDurationMinutes(_ value: Int?) -> Int? {
        guard var minutes = value, minutes > 0 else { return nil }
        minutes = max(30, min(minutes, 8 * 60))
        let remainder = minutes % 30
        if remainder != 0 {
            minutes = minutes - remainder + (remainder >= 15 ? 30 : 0)
        }
        if minutes == 0 {
            return nil
        }
        return minutes
    }

    private func parseDate(_ text: String, calendar: Calendar, locale: Locale) -> Date? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased() == "today" {
            return calendar.startOfDay(for: Date())
        }

        let dateFormats = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"]
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar

        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                if format == "yyyy-MM-dd" {
                    return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
                }
                return date
            }
        }

        return nil
    }

    private func locateTodo(in todos: [TaskItem], from text: String) -> TaskItem? {
        let cleaned = removeControlKeywords(from: text.lowercased())

        let numbers = cleaned
            .split(whereSeparator: { !$0.isWholeNumber })
            .compactMap { Int($0) }

        if let index = numbers.first, todos.indices.contains(index - 1) {
            return todos[index - 1]
        }

        guard !cleaned.isEmpty else { return nil }

        return todos.first { todo in
            todo.title.lowercased().contains(cleaned)
        }
    }

    private func removeControlKeywords(from text: String) -> String {
        var result = text
        let keywords = ["todo", "task", "complete", "done", "toggle", "mark"]
        for keyword in keywords {
            result = result.replacingOccurrences(of: keyword, with: " ")
        }
        return result
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatted(date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func durationSummary(for minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        if hours > 0 && remaining > 0 {
            return "\(hours)h \(remaining)m"
        } else if hours > 0 {
            return "\(hours)h"
        }
        return "\(remaining)m"
    }

    private func formatTodos(_ todos: [TaskItem], calendar: Calendar, locale: Locale, emptyText: String = "No todos registered.", limit: Int? = nil) -> String {
        let items = limit.map { Array(todos.prefix($0)) } ?? todos
        guard !items.isEmpty else {
            return emptyText
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var rows = items.enumerated().map { index, todo in
            let status = todo.isCompleted ? "✅" : "⏳"
            let durationSuffix: String
            if let minutes = todo.estimatedDurationMinutes, minutes > 0 {
                durationSuffix = " · est. \(durationSummary(for: minutes))"
            } else {
                durationSuffix = ""
            }
            let startSuffix: String
            if let start = todo.startDate {
                startSuffix = " · start \(formatter.string(from: start))"
            } else if let minutes = todo.estimatedDurationMinutes, minutes > 0 {
                let inferred = todo.dueDate.addingTimeInterval(-TimeInterval(minutes * 60))
                startSuffix = " · est. start \(formatter.string(from: inferred))"
            } else {
                startSuffix = ""
            }
            let locationSuffix: String
            if let location = todo.location {
                locationSuffix = " · \(location.name)"
            } else {
                locationSuffix = ""
            }
            return "\(index + 1). \(status) \(todo.title) · \(formatter.string(from: todo.dueDate))\(startSuffix)\(locationSuffix) · \(todo.priority.displayName)\(durationSuffix)"
        }

        if let limit, todos.count > limit {
            rows.append("… and \(todos.count - limit) more")
        }

        return rows.joined(separator: "\n")
    }

    private func formatAssignments(_ assignments: [SchoolAssignment], calendar: Calendar, locale: Locale, limit: Int? = nil) -> String {
        let items = limit.map { Array(assignments.prefix($0)) } ?? assignments
        guard !items.isEmpty else {
            return "No assignments imported from Canvas yet."
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var rows = items.enumerated().map { index, assignment in
            let status = assignment.isCompleted ? "✅" : "📚"
            let due = formatter.string(from: assignment.dueDate)
            let course = assignment.course.map { " · \($0)" } ?? ""
            let durationSuffix: String
            if let minutes = assignment.estimatedDurationMinutes, minutes > 0 {
                durationSuffix = " · est. \(durationSummary(for: minutes))"
            } else {
                durationSuffix = ""
            }
            return "\(index + 1). \(status) \(assignment.title)\(course) · \(due)\(durationSuffix)"
        }

        if let limit, assignments.count > limit {
            rows.append("… and \(assignments.count - limit) more")
        }

        return rows.joined(separator: "\n")
    }

    private func formatRoutines(_ routines: [RoutineItem], calendar: Calendar, locale: Locale, limit: Int? = nil) -> String {
        let items = limit.map { Array(routines.prefix($0)) } ?? routines
        guard !items.isEmpty else {
            return "No routines registered."
        }

        var rows = items.enumerated().map { index, routine in
            let status = routine.isEnabled ? "🔁" : "🚫"
            let weekdays = routine.weekdayDisplayString()
            let timeRange = routine.timeRangeString()
            return "\(index + 1). \(status) \(routine.title) · \(weekdays) · \(timeRange)"
        }

        if let limit, routines.count > limit {
            rows.append("… and \(routines.count - limit) more")
        }

        return rows.joined(separator: "\n")
    }
}

private struct AssistantActionEnvelope: Codable {
    let reply: String?
    let actions: [AssistantActionPayload]?
}

private struct AssistantActionPayload: Codable {
    let type: String
    let title: String?
    let dueDate: String?
    let startDate: String?
    let priority: String?
    let identifier: String?
    let durationMinutes: Int?
}
