import SwiftUI
import UniformTypeIdentifiers

private enum TemporalPalette {
    static let ink = Color(red: 0.12, green: 0.10, blue: 0.08)
    static let mutedInk = Color(red: 0.31, green: 0.25, blue: 0.18)
    static let parchment = Color(red: 0.96, green: 0.91, blue: 0.78)
    static let paper = Color(red: 1.0, green: 0.97, blue: 0.87)
    static let amber = Color(red: 0.84, green: 0.45, blue: 0.08)
    static let gold = Color(red: 0.98, green: 0.72, blue: 0.19)
    static let rust = Color(red: 0.54, green: 0.20, blue: 0.08)
    static let green = Color(red: 0.16, green: 0.38, blue: 0.25)
}

private struct TemporalGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(TemporalPalette.rust)
            configuration.content
        }
        .padding(14)
        .background(TemporalPalette.paper.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TemporalPalette.rust.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: TemporalPalette.ink.opacity(0.08), radius: 10, y: 4)
    }
}

private struct ClockworkSeal: View {
    var compact = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(TemporalPalette.gold.opacity(0.9), lineWidth: compact ? 3 : 5)
            Circle()
                .stroke(TemporalPalette.rust.opacity(0.8), lineWidth: 1)
                .padding(compact ? 7 : 12)
            ForEach(0..<12, id: \.self) { tick in
                Capsule()
                    .fill(TemporalPalette.gold)
                    .frame(width: compact ? 2 : 3, height: compact ? 7 : 11)
                    .offset(y: compact ? -15 : -25)
                    .rotationEffect(.degrees(Double(tick) * 30))
            }
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.system(size: compact ? 16 : 30, weight: .semibold))
                .foregroundStyle(TemporalPalette.gold)
        }
        .frame(width: compact ? 42 : 72, height: compact ? 42 : 72)
        .background(TemporalPalette.ink, in: Circle())
        .overlay(Circle().stroke(TemporalPalette.gold.opacity(0.65), lineWidth: 1))
    }
}

private struct TemporalMasthead: View {
    let modelName: String
    let runtimeSummary: String
    let isLocal: Bool

    var body: some View {
        HStack(spacing: 14) {
            ClockworkSeal(compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("ALEXI")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .tracking(3)
                Text("CHRONOLOGICAL OPERATIONS DESK")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .tracking(1)
                    .foregroundStyle(TemporalPalette.mutedInk)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Label(isLocal ? "LOCAL TIME AUTHORITY" : "EXTERNAL RELAY", systemImage: isLocal ? "lock.fill" : "network")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(isLocal ? TemporalPalette.green : TemporalPalette.rust)
                Text("\(modelName)  •  \(runtimeSummary)")
                    .font(.caption2)
                    .foregroundStyle(TemporalPalette.mutedInk)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(TemporalPalette.parchment.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LinearGradient(colors: [TemporalPalette.rust, TemporalPalette.gold, TemporalPalette.rust], startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)
        }
    }
}

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
        ZStack {
            LinearGradient(
                colors: [TemporalPalette.parchment, Color(red: 0.90, green: 0.80, blue: 0.57), TemporalPalette.parchment],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TemporalMasthead(
                    modelName: modelSettings.activeModelName,
                    runtimeSummary: modelSettings.runtimeSummary,
                    isLocal: modelSettings.backend == .localOllama
                )
                HStack(spacing: 0) {
                    sidebar
                        .frame(minWidth: 288, idealWidth: 320, maxWidth: 370)
                        .background(TemporalPalette.parchment.opacity(0.72))
                    Rectangle()
                        .fill(TemporalPalette.rust.opacity(0.22))
                        .frame(width: 1)
                    centerPanel
                    Rectangle()
                        .fill(TemporalPalette.rust.opacity(0.22))
                        .frame(width: 1)
                    inspectorPanel
                        .frame(minWidth: 272, idealWidth: 310, maxWidth: 370)
                        .background(TemporalPalette.parchment.opacity(0.72))
                }
            }
        }
        .frame(minWidth: 1200, minHeight: 720)
        .tint(TemporalPalette.amber)
        .foregroundStyle(TemporalPalette.ink)
        .groupBoxStyle(TemporalGroupBoxStyle())
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
                GroupBox("Case file") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(workspaceStore.rootURL?.path ?? "No case file selected")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Open case file", systemImage: "folder.badge.gearshape") { showingWorkspacePicker = true }
                            Button("Refresh", systemImage: "arrow.clockwise") { workspaceStore.reloadFiles() }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                GroupBox("Authority status") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(modelSettings.runtimeSummary, systemImage: modelSettings.backend == .localOllama ? "lock.shield.fill" : "network")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(modelSettings.backend == .localOllama ? .green : .orange)
                        Text("ACTIVE ENGINE  //  \(modelSettings.activeModelName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open control room", systemImage: "slider.horizontal.3") { showingModelSettings = true }
                            .buttonStyle(.bordered)
                    }
                }

                GroupBox("Archive search") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Search the case file", text: $workspaceSearchQuery)
                        HStack {
                            Button("Search archive", systemImage: "magnifyingglass") {
                                workspaceStore.searchWorkspace(query: workspaceSearchQuery)
                                workspaceStore.addAction("Search query", detail: workspaceSearchQuery)
                            }
                            Button("Brief me", systemImage: "text.badge.checkmark") {
                                let summary = workspaceStore.summarizeWorkspace()
                                messages.append(ChatMessage(role: .assistant, content: summary))
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                GroupBox("Evidence index") {
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

                GroupBox("Private record") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(memoryStore.memories.prefix(4)) { memory in
                            Text(memory.content)
                                .lineLimit(2)
                        }
                        Button("Review record", systemImage: "lock.doc") { showingMemoryReview = true }
                    }
                }

                GroupBox("Field protocols") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Mode", selection: $companion.selectedMode) {
                            ForEach(CompanionMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        Button("Daily check-in", systemImage: "checkmark.circle") { showingCheckIn = true }
                        Button("DSA briefing", systemImage: "brain.head.profile") { showingDSAPlan = true }
                        Button("Focus session", systemImage: "timer") { showingPracticeWorkspace = true }
                        Button("Daily routines", systemImage: "bell.badge") { showingRoutines = true }
                    }
                }

                GroupBox("Audit trail") {
                    Button("Review activity & access", systemImage: "checklist") { showingActivity = true }
                }

                GroupBox("Variance proposal") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("01  SELECT EVIDENCE   02  DESCRIBE VARIANCE   03  REVIEW PLAN   04  APPLY MANUALLY")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Describe the variance to investigate…", text: $patchInstruction, axis: .vertical)
                            .lineLimit(2...4)
                        Button("Log a local proposal", systemImage: "note.text.badge.plus") {
                            workspaceStore.proposePatch(instruction: patchInstruction)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Generate reviewable plan", systemImage: "sparkles") {
                            generatePatchDraft()
                        }
                        .buttonStyle(.bordered)
                        Button("Load evidence into draft", systemImage: "doc.text") {
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
                        Text(modelSettings.orchestrationSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Apply reviewed draft", systemImage: "checkmark.seal.fill") {
                                _ = workspaceStore.applySelectedFileDraft()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Add to docket", systemImage: "plus") {
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
            HStack(alignment: .center, spacing: 14) {
                ClockworkSeal()
                VStack(alignment: .leading, spacing: 5) {
                    Text("OPERATIONS CONSOLE")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(TemporalPalette.rust)
                    Text(workspaceStore.rootURL?.lastPathComponent ?? "Awaiting a case file")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text("Local analysis. Clear audit trail. Your approval controls every change.")
                        .font(.footnote)
                        .foregroundStyle(TemporalPalette.mutedInk)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Label(isResponding ? "ANALYSING" : "TIME STREAM STABLE", systemImage: isResponding ? "hourglass" : "checkmark.seal.fill")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(isResponding ? TemporalPalette.rust : TemporalPalette.green)
                    Text(voiceService.voiceStatus)
                        .font(.caption2)
                        .foregroundStyle(TemporalPalette.mutedInk)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.count == 1 {
                        temporalWelcome
                    }
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                    if isResponding {
                        ProgressView("Alexi is tracing the timeline…")
                            .tint(TemporalPalette.amber)
                    }
                }
                .padding(24)
            }

            Rectangle()
                .fill(TemporalPalette.rust.opacity(0.22))
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("NEW TRANSMISSION")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(TemporalPalette.rust)
                TextField("Ask Alexi to inspect, explain, or plan…", text: $draft, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(10)
                    .background(TemporalPalette.paper.opacity(0.84), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(TemporalPalette.rust.opacity(0.28), lineWidth: 1)
                    }
                HStack(alignment: .bottom) {
                    Button(action: toggleListening) {
                        Label(voiceService.isVoiceModeEnabled ? "Close channel" : "Open voice channel", systemImage: voiceService.isVoiceModeEnabled ? "stop.circle.fill" : "mic.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .help(voiceService.isVoiceModeEnabled ? "End continuous voice mode" : "Start continuous voice mode")
                    if voiceService.isSpeaking {
                        Button(action: voiceService.interruptAndListen) {
                            Label("Interrupt & speak", systemImage: "waveform.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Stop Alexi and start listening")
                    }
                    Button(action: send) {
                        Label("Transmit", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding)
                    Spacer()
                }
            }
            .padding(18)
            .background(TemporalPalette.parchment.opacity(0.84))
        }
    }

    private var temporalWelcome: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(TemporalPalette.gold)
                .frame(width: 50, height: 50)
                .background(TemporalPalette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Your timeline is clear.")
                    .font(.headline)
                Text("Open a case file or send a request. Alexi will keep the investigation local and make every proposed change reviewable.")
                    .font(.caption)
                    .foregroundStyle(TemporalPalette.mutedInk)
            }
        }
        .padding(14)
        .background(TemporalPalette.gold.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TemporalPalette.amber.opacity(0.4), lineWidth: 1)
        }
    }

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Selected evidence") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(workspaceStore.selectedFileSummary)
                            .font(.footnote)
                        if let selectedFile = workspaceStore.selectedFile {
                            Text(selectedFile.url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !workspaceStore.searchResults.isEmpty {
                            Text("Archive matches")
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

                GroupBox("Timeline record") {
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

                GroupBox("Instrument panel") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(workspaceStore.toolCalls.prefix(10)) { call in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(call.toolName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(call.wasSuccessful ? "CLEARED" : "FLAGGED")
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

                GroupBox("Temporal docket") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today’s appointments")
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
                            Text("No appointments on the docket")
                                .foregroundStyle(.secondary)
                        }
                        Text("Open reminders")
                            .font(.subheadline.weight(.semibold))
                        ForEach(organizer.incompleteReminders.prefix(4)) { reminder in
                            Text(reminder.title)
                        }
                        if organizer.incompleteReminders.isEmpty {
                            Text("No open reminders")
                                .foregroundStyle(.secondary)
                        }
                        Button("Refresh docket", systemImage: "arrow.clockwise") {
                            Task { await organizer.refresh() }
                        }
                    }
                }

                GroupBox("Active directives") {
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
        activityStore.record(category: "Model", action: "Sent model request", destination: modelSettings.requestDestination)
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
        activityStore.record(category: "Orchestration", action: "Requested patch plan", destination: modelSettings.patchPlanDestination)
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
                    Button(modelSettings.isDiscoveringLocalModels ? "Discovering local models…" : "Discover local models") {
                        Task { await modelSettings.discoverLocalModels() }
                    }
                    .disabled(modelSettings.isDiscoveringLocalModels)
                    if !modelSettings.installedLocalModels.isEmpty {
                        Picker("Installed model", selection: $modelSettings.localModel) {
                            ForEach(modelSettings.installedLocalModels) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                    }
                    Text("Local-only mode sends prompts to your Ollama server and has no hosted API charges. Your hardware and electricity still power inference.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Patch-plan orchestration") {
                    Picker("Planner", selection: $modelSettings.orchestrationBackend) {
                        ForEach(OrchestrationBackend.allCases) { backend in
                            Text(backend.rawValue).tag(backend)
                        }
                    }
                    Text("Both planners are plan-only. Alexi does not apply or execute model-generated changes automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if modelSettings.orchestrationBackend == .langGraphLocal {
                        TextField("LangGraph endpoint", text: $modelSettings.langGraphEndpoint)
                        Button(modelSettings.isCheckingLangGraph ? "Checking sidecar…" : "Check local sidecar") {
                            Task { await modelSettings.checkLangGraph() }
                        }
                        .disabled(modelSettings.isCheckingLangGraph)
                        Text("LangGraph runs only on localhost and calls your local Ollama model. It cannot write workspace files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(modelSettings.langGraphStatus)
                            .font(.caption)
                            .foregroundStyle(modelSettings.langGraphStatus.hasPrefix("Ready") ? .green : .secondary)
                    }
                }
                Section("Remote") {
                    TextField("Endpoint", text: $modelSettings.remoteEndpoint)
                    TextField("Model", text: $modelSettings.remoteModel)
                    SecureField("API key", text: $modelSettings.apiKey)
                }
                Section("Status") {
                    Text(modelSettings.statusMessage)
                    Text(modelSettings.runtimeSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .frame(width: 600, height: 560)
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
            HStack(alignment: .top, spacing: 9) {
                if message.role == .assistant {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TemporalPalette.gold)
                        .frame(width: 24, height: 24)
                        .background(TemporalPalette.ink, in: Circle())
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.role == .assistant ? "ALEXI // OFFICIAL RESPONSE" : "YOU // INCOMING TRANSMISSION")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(message.role == .assistant ? TemporalPalette.rust : TemporalPalette.paper.opacity(0.82))
                    Text(message.content)
                        .textSelection(.enabled)
                        .font(.body)
                }
            }
            .padding(14)
            .background(message.role == .user ? TemporalPalette.ink : TemporalPalette.paper.opacity(0.9))
            .foregroundStyle(message.role == .user ? TemporalPalette.paper : TemporalPalette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(message.role == .user ? TemporalPalette.gold.opacity(0.65) : TemporalPalette.rust.opacity(0.26), lineWidth: 1)
            }
            if message.role == .assistant { Spacer(minLength: 80) }
        }
    }
}
