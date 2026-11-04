import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(ActivityStore.self) private var activityStore
    @Environment(WorkspaceStore.self) private var workspaceStore
    @Environment(ModelSettingsStore.self) private var modelSettings
    @State private var messages: [ChatMessage] = [
        ChatMessage(role: .assistant, content: "I'm Alexi. I run locally on this Mac. Point me at a workspace and I can help you think through the code.")
    ]
    @State private var draft = ""
    @State private var isResponding = false
    @State private var newMemory = ""
    @State private var voiceService = VoiceService()
    @State private var organizer = OrganizerService()
    @State private var companion = CompanionStore()
    @State private var eventTitle = ""
    @State private var eventStart = Date.now
    @State private var eventEnd = Date.now.addingTimeInterval(60 * 60)
    @State private var reminderTitle = ""
    @State private var reminderDueDate = Date.now
    @State private var hasReminderDueDate = false
    @State private var pendingAction: OrganizerAction?
    @State private var showingCheckIn = false
    @State private var showingDSAPlan = false
    @State private var showingMemoryReview = false
    @State private var showingRoutines = false
    @State private var showingPracticeWorkspace = false
    @State private var showingActivity = false
    @State private var showingModelSettings = false
    @State private var showingWorkspacePicker = false
    @State private var workspacePrompt = "Ask me about the workspace, a file, or the next coding step."
    @State private var workspaceSearchQuery = ""
    @State private var patchInstruction = ""
    @State private var generatedPatchStatus = "No generated patch yet."
    @State private var routines = RoutineService()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            Divider()
            centerPanel
            Divider()
            inspectorPanel
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        }
        .frame(minWidth: 1200, minHeight: 720)
        .onChange(of: voiceService.transcript) { _, transcript in
            draft = transcript
        }
        .onChange(of: voiceService.finalizedTranscript) { _, transcript in
            guard let transcript else { return }
            voiceService.clearFinalizedTranscript()
            send(transcript)
        }
        .task {
            await organizer.refresh()
        }
        .sheet(item: $pendingAction) { action in
            OrganizerForm(action: action, eventTitle: $eventTitle, eventStart: $eventStart, eventEnd: $eventEnd, reminderTitle: $reminderTitle, reminderDueDate: $reminderDueDate, hasReminderDueDate: $hasReminderDueDate) { confirmedAction in
                Task { await perform(confirmedAction) }
            }
        }
        .sheet(isPresented: $showingCheckIn) {
            DailyCheckInForm { mood, note, focus in
                companion.addCheckIn(mood: mood, note: note, focus: focus)
            }
        }
        .sheet(isPresented: $showingDSAPlan) {
            DSAPlanForm(profile: $companion.dsaProfile) {
                companion.recordSolvedProblem()
            }
        }
        .sheet(isPresented: $showingMemoryReview) {
            MemoryReviewView()
                .environment(memoryStore)
        }
        .sheet(isPresented: $showingRoutines) {
            RoutinesView()
                .environment(routines)
        }
        .sheet(isPresented: $showingPracticeWorkspace) {
            DSAPracticeWorkspace()
                .environment(companion)
        }
        .sheet(isPresented: $showingActivity) {
            ActivityAuditView()
                .environment(activityStore)
        }
        .sheet(isPresented: $showingModelSettings) {
            ModelSettingsView(modelSettings: modelSettings)
        }
        .fileImporter(
            isPresented: $showingWorkspacePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                workspaceStore.openWorkspace(at: url)
            }
        }
        .onAppear {
            workspaceStore.openSuggestedWorkspace()
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Workspace") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(workspaceStore.rootURL?.path ?? "No workspace selected")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Choose folder") { showingWorkspacePicker = true }
                            Button("Reload") { workspaceStore.reloadFiles() }
                        }
                        .buttonStyle(.bordered)
                        Button("Model settings") { showingModelSettings = true }
                            .buttonStyle(.bordered)
                    }
                }

                GroupBox("Search") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Search workspace", text: $workspaceSearchQuery)
                        HStack {
                            Button("Search") {
                                workspaceStore.searchWorkspace(query: workspaceSearchQuery)
                                workspaceStore.addAction("Search query", detail: workspaceSearchQuery)
                            }
                            Button("Summarize") {
                                let summary = workspaceStore.summarizeWorkspace()
                                messages.append(ChatMessage(role: .assistant, content: summary))
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                GroupBox("Files") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(workspaceStore.files.prefix(18)) { file in
                            Button {
                                workspaceStore.select(file)
                            } label: {
                                HStack {
                                    Image(systemName: file.isDirectory ? "folder" : "doc.text")
                                    Text(file.name)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                GroupBox("Private Memory") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(memoryStore.memories.prefix(4)) { memory in
                            Text(memory.content)
                                .lineLimit(2)
                        }
                        Button("Review all memory") { showingMemoryReview = true }
                    }
                }

                GroupBox("Companion") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Mode", selection: $companion.selectedMode) {
                            ForEach(CompanionMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        Button("Daily check-in") { showingCheckIn = true }
                        Button("DSA plan") { showingDSAPlan = true }
                        Button("DSA focus session") { showingPracticeWorkspace = true }
                        Button("Daily routines") { showingRoutines = true }
                    }
                }

                GroupBox("Security") {
                    Button("Activity & access") { showingActivity = true }
                }

                GroupBox("Patch Draft") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("What should change?", text: $patchInstruction, axis: .vertical)
                            .lineLimit(2...4)
                        Button("Propose patch") {
                            workspaceStore.proposePatch(instruction: patchInstruction)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Generate safe patch plan") {
                            generatePatchDraft()
                        }
                        .buttonStyle(.bordered)
                        Button("Load selected file into draft") {
                            workspaceStore.loadSelectedFileDraft()
                        }
                        .buttonStyle(.bordered)
                        TextEditor(text: Binding(
                            get: { workspaceStore.selectedFileDraft },
                            set: { workspaceStore.updateSelectedFileDraft($0) }
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 150)
                        .scrollContentBackground(.hidden)
                        Text(workspaceStore.selectedFileDraftStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(generatedPatchStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Apply reviewed draft") {
                                _ = workspaceStore.applySelectedFileDraft()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Add task") {
                                workspaceStore.addTask(title: patchInstruction, detail: "Track the change before applying it")
                            }
                            .buttonStyle(.bordered)
                        }
                        ForEach(workspaceStore.patchProposals.prefix(3)) { proposal in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(proposal.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(proposal.proposedChange)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(6)
                            }
                            Divider()
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Alexi")
    }

    private var centerPanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace Assistant")
                        .font(.title2.weight(.semibold))
                    Text(workspacePrompt)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(voiceService.voiceStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                    if isResponding {
                        ProgressView("Alexi is thinking…")
                    }
                }
                .padding()
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                TextField("Ask Alexi about this workspace", text: $draft, axis: .vertical)
                    .lineLimit(2...5)
                HStack(alignment: .bottom) {
                    Button(action: toggleListening) {
                        Label(voiceService.isVoiceModeEnabled ? "End voice mode" : "Voice mode", systemImage: voiceService.isVoiceModeEnabled ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.title2)
                    }
                    .help(voiceService.isVoiceModeEnabled ? "End continuous voice mode" : "Start continuous voice mode")
                    if voiceService.isSpeaking {
                        Button(action: voiceService.interruptAndListen) {
                            Label("Interrupt & speak", systemImage: "waveform.circle.fill")
                                .font(.title2)
                        }
                        .help("Stop Alexi and start listening")
                    }
                    Button(action: send) {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding)
                    Spacer()
                }
            }
            .padding()
        }
    }

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Selected Context") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(workspaceStore.selectedFileSummary)
                            .font(.footnote)
                        if let selectedFile = workspaceStore.selectedFile {
                            Text(selectedFile.url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !workspaceStore.searchResults.isEmpty {
                            Text("Search results")
                                .font(.headline)
                            ForEach(workspaceStore.searchResults.prefix(8)) { result in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(result.file.name):\(result.lineNumber)")
                                        .font(.caption.weight(.semibold))
                                    Text(result.line)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                        TextEditor(text: .constant(workspaceStore.selectedFileContents))
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                            .disabled(true)
                    }
                }

                GroupBox("Action Log") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(workspaceStore.actions.prefix(10)) { action in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(action.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                GroupBox("Tool Calls") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(workspaceStore.toolCalls.prefix(10)) { call in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(call.toolName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(call.wasSuccessful ? "ok" : "fail")
                                        .font(.caption)
                                        .foregroundStyle(call.wasSuccessful ? .green : .red)
                                }
                                Text(call.input)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(call.output)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            Divider()
                        }
                    }
                }

                GroupBox("Organizer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today")
                            .font(.subheadline.weight(.semibold))
                        ForEach(organizer.todaysEvents.prefix(4)) { event in
                            VStack(alignment: .leading) {
                                Text(event.title)
                                Text(event.startDate, format: .dateTime.hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if organizer.todaysEvents.isEmpty {
                            Text("No events today")
                                .foregroundStyle(.secondary)
                        }
                        Text("Reminders")
                            .font(.subheadline.weight(.semibold))
                        ForEach(organizer.incompleteReminders.prefix(4)) { reminder in
                            Text(reminder.title)
                        }
                        if organizer.incompleteReminders.isEmpty {
                            Text("No open reminders")
                                .foregroundStyle(.secondary)
                        }
                        Button("Refresh organizer") {
                            Task { await organizer.refresh() }
                        }
                    }
                }

                GroupBox("Tasks") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(workspaceStore.tasks) { task in
                            Button {
                                workspaceStore.toggleTask(task)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title)
                                            .font(.subheadline.weight(.semibold))
                                            .strikethrough(task.isDone)
                                        Text(task.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func send() {
        send(draft)
    }

    private func send(_ message: String) {
        let prompt = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        draft = ""
        messages.append(ChatMessage(role: .user, content: prompt))
        activityStore.record(category: "Network", action: "Sent a local model request", destination: "Ollama on localhost:11434")
        workspaceStore.addAction("Asked Alexi", detail: prompt)
        isResponding = true

        Task {
            do {
                let response = try await ModelRouter.reply(
                    to: prompt,
                    mode: companion.selectedMode,
                    context: ModelReplyContext(
                        memoryContext: memoryStore.context,
                        companionContext: companion.context,
                        workspaceContext: workspaceContext
                    ),
                    settings: modelSettings.snapshot
                )
                messages.append(ChatMessage(role: .assistant, content: response))
                workspaceStore.addAction("Responded", detail: response)
                if voiceService.isVoiceModeEnabled {
                    voiceService.speak(response)
                }
            } catch {
                messages.append(ChatMessage(role: .assistant, content: error.localizedDescription))
                workspaceStore.addAction("Model error", detail: error.localizedDescription)
            }
            isResponding = false
        }
    }

    private func toggleListening() {
        if voiceService.isVoiceModeEnabled {
            voiceService.stopVoiceMode()
        } else {
            Task {
                await voiceService.startVoiceMode()
            }
        }
    }

    private func perform(_ action: OrganizerAction) async {
        do {
            switch action {
            case .event:
                try await organizer.createEvent(title: eventTitle, startDate: eventStart, endDate: eventEnd)
                eventTitle = ""
            case .reminder:
                try await organizer.createReminder(title: reminderTitle, dueDate: hasReminderDueDate ? reminderDueDate : nil)
                reminderTitle = ""
            }
        } catch {
            organizer.statusMessage = error.localizedDescription
        }
    }

    private func generatePatchDraft() {
        let instruction = patchInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, let selectedFile = workspaceStore.selectedFile, !selectedFile.isDirectory else {
            generatedPatchStatus = "Pick a text file and enter an instruction first."
            workspaceStore.recordToolFailure(toolName: "draft_patch", input: patchInstruction, output: generatedPatchStatus)
            return
        }

        generatedPatchStatus = "Generating a reviewable patch plan..."
        Task {
            do {
                let plan = try await ModelRouter.draftPatch(
                    instruction: instruction,
                    selectedFilePath: selectedFile.url.path,
                    selectedFileContents: workspaceStore.selectedFileContents,
                    workspaceContext: workspaceContext,
                    settings: modelSettings.snapshot
                )
                workspaceStore.setGeneratedPatchPlan(plan, instruction: instruction)
                generatedPatchStatus = "Generated a patch plan. Review it, then edit the local draft before applying anything."
            } catch {
                generatedPatchStatus = error.localizedDescription
                workspaceStore.recordToolFailure(toolName: "draft_patch", input: instruction, output: error.localizedDescription)
            }
        }
    }

    private var workspaceContext: String {
        var lines: [String] = []
        if let rootURL = workspaceStore.rootURL {
            lines.append("Workspace root: \(rootURL.path)")
        }
        if let selectedFile = workspaceStore.selectedFile {
            lines.append("Selected item: \(selectedFile.url.lastPathComponent)")
            lines.append("Selected path: \(selectedFile.url.path)")
            lines.append("Selected preview:")
            lines.append(workspaceStore.selectedFileContents.prefix(1800).description)
            lines.append("Current draft:")
            lines.append(workspaceStore.selectedFileDraft.prefix(1800).description)
        }
        if !workspaceStore.files.isEmpty {
            let sample = workspaceStore.files.prefix(12).map { $0.name }.joined(separator: ", ")
            lines.append("Visible files: \(sample)")
        }
        return lines.joined(separator: "\n")
    }
}

private struct ModelSettingsView: View {
    @Bindable var modelSettings: ModelSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Backend", selection: $modelSettings.backend) {
                    ForEach(ModelBackend.allCases) { backend in
                        Text(backend.rawValue).tag(backend)
                    }
                }
                Section("Local Ollama") {
                    TextField("Endpoint", text: $modelSettings.localEndpoint)
                    TextField("Model", text: $modelSettings.localModel)
                }
                Section("Remote") {
                    TextField("Endpoint", text: $modelSettings.remoteEndpoint)
                    TextField("Model", text: $modelSettings.remoteModel)
                    SecureField("API key", text: $modelSettings.apiKey)
                }
                Section("Status") {
                    Text(modelSettings.statusMessage)
                }
            }
            .navigationTitle("Model Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        modelSettings.statusMessage = "Using \(modelSettings.backend.rawValue) with \(modelSettings.activeModelName)"
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 560, height: 420)
    }
}

private struct ActivityAuditView: View {
    @Environment(ActivityStore.self) private var activityStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Access policy") {
                    Text("Allowed: microphone, Calendar/Reminders, local notifications, and the local Ollama server.")
                    Text("Blocked by sandbox: browser history, saved passwords, general files, contacts, camera, location, and cloud accounts.")
                }
                Section("Activity log") {
                    if activityStore.entries.isEmpty {
                        Text("No activity recorded yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(activityStore.entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.action)
                            Text(entry.destination)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.date, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("Activity & access")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear log", role: .destructive) { activityStore.clear() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 560, height: 500)
    }
}

private struct MemoryReviewView: View {
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(memoryStore.memories) { memory in
                    MemoryReviewRow(memory: memory)
                }
            }
            .navigationTitle("Review private memory")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 520, height: 440)
    }
}

private struct MemoryReviewRow: View {
    @Environment(MemoryStore.self) private var memoryStore
    let memory: Memory
    @State private var content: String

    init(memory: Memory) {
        self.memory = memory
        _content = State(initialValue: memory.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Memory", text: $content, axis: .vertical)
            HStack {
                Text(memory.createdAt, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") { memoryStore.update(id: memory.id, content: content) }
                Button("Forget", role: .destructive) { memoryStore.delete(memory) }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RoutinesView: View {
    @Environment(RoutineService.self) private var routines
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var routines = routines
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily routines")
                .font(.title2)
            Text("Alexi can send two local reminders each day. Nothing is sent to a server.")
                .foregroundStyle(.secondary)
            Stepper("Morning check-in: \(routines.morningHour):00", value: $routines.morningHour, in: 5...12)
            Stepper("Evening reflection: \(routines.eveningHour):00", value: $routines.eveningHour, in: 17...23)
            if let statusMessage = routines.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Disable") { routines.disableDailyRoutines() }
                Spacer()
                Button("Enable daily check-ins") {
                    Task { await routines.enableDailyRoutines() }
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Done") { dismiss() }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct DSAPracticeWorkspace: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @State private var problem = ""
    @State private var topic = ""
    @State private var notes = ""
    @State private var solved = false
    @State private var startedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 16) {
                Text("DSA focus session")
                    .font(.title2)
                TextField("Problem name or link", text: $problem)
                TextField("Topic", text: $topic)
                if let startedAt {
                    Text("Focused for \(elapsedMinutes(since: startedAt, now: timeline.date)) min")
                        .font(.title3.monospacedDigit())
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .border(.secondary.opacity(0.3))
                    Toggle("Solved it", isOn: $solved)
                    HStack {
                        Button("Discard session") { dismiss() }
                        Spacer()
                        Button("Finish and save") {
                            companion.recordPractice(problem: problem, topic: topic, notes: notes, minutes: elapsedMinutes(since: startedAt, now: timeline.date), solved: solved)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text("Alexi will record the time and keep your notes locally. Ask in DSA Coach mode whenever you want a hint.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Start focus") { startedAt = .now }
                            .buttonStyle(.borderedProminent)
                            .disabled(problem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(24)
            .frame(width: 460)
        }
    }

    private func elapsedMinutes(since start: Date, now: Date) -> Int {
        max(1, Int(now.timeIntervalSince(start) / 60))
    }
}

private struct DailyCheckInForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mood = 3
    @State private var note = ""
    @State private var focus = ""
    let save: (Int, String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily check-in")
                .font(.title2)
            Stepper("Mood: \(mood)/5", value: $mood, in: 1...5)
            TextField("How are you feeling?", text: $note, axis: .vertical)
                .lineLimit(2...4)
            TextField("What matters most today?", text: $focus)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save check-in") {
                    save(mood, note, focus)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct DSAPlanForm: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var profile: DSAProfile
    let recordSolved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DSA coaching plan")
                .font(.title2)
            TextField("Current topic", text: $profile.currentTopic)
            Stepper("Confidence: \(profile.confidence)/5", value: $profile.confidence, in: 1...5)
            Stepper("Weekly problem goal: \(profile.weeklyGoal)", value: $profile.weeklyGoal, in: 1...20)
            Text("Completed this week: \(profile.solvedThisWeek)")
            Button("Record solved problem") {
                recordSolved()
            }
            .buttonStyle(.bordered)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private enum OrganizerAction: String, Identifiable {
    case event
    case reminder

    var id: String { rawValue }
}

private struct OrganizerForm: View {
    let action: OrganizerAction
    @Binding var eventTitle: String
    @Binding var eventStart: Date
    @Binding var eventEnd: Date
    @Binding var reminderTitle: String
    @Binding var reminderDueDate: Date
    @Binding var hasReminderDueDate: Bool
    @Environment(\.dismiss) private var dismiss
    let confirm: (OrganizerAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(action == .event ? "Create calendar event" : "Create reminder")
                .font(.title2)
            if action == .event {
                TextField("Title", text: $eventTitle)
                DatePicker("Starts", selection: $eventStart)
                DatePicker("Ends", selection: $eventEnd)
            } else {
                TextField("Title", text: $reminderTitle)
                Toggle("Set due date", isOn: $hasReminderDueDate)
                if hasReminderDueDate {
                    DatePicker("Due", selection: $reminderDueDate)
                }
            }
            Text("Alexi will create this only after you confirm.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Confirm and create") {
                    confirm(action)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (action == .event && eventEnd <= eventStart))
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var title: String {
        action == .event ? eventTitle : reminderTitle
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 80) }
            Text(message.content)
                .textSelection(.enabled)
                .padding(12)
                .background(message.role == .user ? Color.accentColor : Color.gray.opacity(0.16))
                .foregroundStyle(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if message.role == .assistant { Spacer(minLength: 80) }
        }
    }
}
