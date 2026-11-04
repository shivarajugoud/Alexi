import Foundation
import Observation

struct WorkspaceFile: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
}

struct WorkspaceAction: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let title: String
    let detail: String

    init(date: Date = .now, title: String, detail: String) {
        self.date = date
        self.title = title
        self.detail = detail
    }
}

struct ToolCallEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let toolName: String
    let input: String
    let output: String
    let wasSuccessful: Bool

    init(date: Date = .now, toolName: String, input: String, output: String, wasSuccessful: Bool) {
        self.date = date
        self.toolName = toolName
        self.input = input
        self.output = output
        self.wasSuccessful = wasSuccessful
    }
}

struct WorkspaceSearchResult: Identifiable, Hashable {
    let id = UUID()
    let file: WorkspaceFile
    let lineNumber: Int
    let line: String
    let score: Int
}

struct PatchProposal: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let summary: String
    let targetPath: String
    let proposedChange: String
}

struct WorkspaceTask: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var detail: String
    var isDone: Bool = false
}

@MainActor
@Observable
final class WorkspaceStore {
    private(set) var rootURL: URL?
    private(set) var files: [WorkspaceFile] = []
    private(set) var selectedFile: WorkspaceFile?
    private(set) var selectedFileContents: String = "Select a text file to preview it here."
    private(set) var selectedFileDraft: String = "Select a text file to begin an edit draft."
    private(set) var selectedFileDraftStatus: String = "No draft loaded."
    private(set) var searchResults: [WorkspaceSearchResult] = []
    private(set) var patchProposals: [PatchProposal] = []
    private(set) var toolCalls: [ToolCallEntry] = [
        ToolCallEntry(toolName: "startup", input: "workspace", output: "Ready", wasSuccessful: true)
    ]
    private(set) var tasks: [WorkspaceTask] = [
        WorkspaceTask(title: "Pick a workspace", detail: "Open a folder to inspect files"),
        WorkspaceTask(title: "Search for context", detail: "Use workspace search before editing"),
        WorkspaceTask(title: "Draft a patch", detail: "Prepare a safe edit for a text file")
    ]
    private(set) var actions: [WorkspaceAction] = [
        WorkspaceAction(title: "Ready", detail: "Choose a folder to inspect your workspace")
    ]

    func openSuggestedWorkspace() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Documents/Alexi"),
            home.appendingPathComponent("Documents"),
            home
        ]
        if let existing = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            openWorkspace(at: existing)
        }
    }

    func openWorkspace(at url: URL) {
        rootURL = url
        selectedFile = nil
        selectedFileContents = "Select a text file to preview it here."
        selectedFileDraft = "Select a text file to begin an edit draft."
        selectedFileDraftStatus = "No draft loaded."
        searchResults = []
        actions.insert(WorkspaceAction(title: "Workspace opened", detail: url.path), at: 0)
        reloadFiles()
    }

    func reloadFiles() {
        guard let rootURL else {
            files = []
            return
        }

        let manager = FileManager.default
        let urls = (try? manager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        files = urls
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return WorkspaceFile(
                    id: url,
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: values?.isDirectory ?? false
                )
            }
    }

    func select(_ file: WorkspaceFile) {
        selectedFile = file
        actions.insert(WorkspaceAction(title: "Selected file", detail: file.url.path), at: 0)
        loadSelectedFileContents()
        loadSelectedFileDraft()
    }

    func addAction(_ title: String, detail: String) {
        actions.insert(WorkspaceAction(title: title, detail: detail), at: 0)
    }

    func recordToolCall(toolName: String, input: String, output: String, wasSuccessful: Bool) {
        toolCalls.insert(ToolCallEntry(toolName: toolName, input: input, output: output, wasSuccessful: wasSuccessful), at: 0)
        toolCalls = Array(toolCalls.prefix(100))
    }

    var selectedFileSummary: String {
        guard let selectedFile else { return "No file selected." }
        return selectedFile.isDirectory ? "Folder: \(selectedFile.name)" : "File: \(selectedFile.name)"
    }

    func loadSelectedFileContents() {
        guard let selectedFile else {
            selectedFileContents = "Select a text file to preview it here."
            return
        }
        guard !selectedFile.isDirectory else {
            selectedFileContents = "Folders do not have file contents. Open a file inside this folder."
            return
        }

        let url = selectedFile.url
        guard let data = try? Data(contentsOf: url) else {
            selectedFileContents = "Alexi could not read this file."
            return
        }

        if let text = String(data: data, encoding: .utf8), text.count <= 60_000 {
            selectedFileContents = text
        } else {
            selectedFileContents = "This file does not look like a small UTF-8 text file, so Alexi is leaving it untouched."
        }
    }

    func loadSelectedFileDraft() {
        guard let selectedFile else {
            selectedFileDraft = "Select a text file to begin an edit draft."
            selectedFileDraftStatus = "No draft loaded."
            return
        }
        guard !selectedFile.isDirectory else {
            selectedFileDraft = "Folders cannot be edited."
            selectedFileDraftStatus = "Folder selected."
            return
        }
        selectedFileDraft = selectedFileContents
        selectedFileDraftStatus = "Draft loaded from \(selectedFile.name)."
    }

    func updateSelectedFileDraft(_ draft: String) {
        selectedFileDraft = draft
        selectedFileDraftStatus = "Draft changed locally."
    }

    func applySelectedFileDraft() -> Bool {
        guard let selectedFile, !selectedFile.isDirectory else { return false }
        guard selectedFileDraft != selectedFileContents else {
            selectedFileDraftStatus = "No changes to apply."
            return false
        }
        guard let data = selectedFileDraft.data(using: .utf8) else {
            selectedFileDraftStatus = "Draft is not valid UTF-8."
            return false
        }
        guard let rootURL, selectedFile.url.path.hasPrefix(rootURL.path) else {
            selectedFileDraftStatus = "Selected file is outside the workspace."
            return false
        }
        do {
            try data.write(to: selectedFile.url, options: [.atomic])
            selectedFileContents = selectedFileDraft
            actions.insert(WorkspaceAction(title: "Applied patch", detail: selectedFile.url.path), at: 0)
            selectedFileDraftStatus = "Applied changes to \(selectedFile.name)."
            reloadFiles()
            return true
        } catch {
            selectedFileDraftStatus = "Could not apply draft: \(error.localizedDescription)"
            return false
        }
    }

    func searchWorkspace(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, let rootURL else {
            searchResults = []
            recordToolCall(toolName: "search_workspace", input: query, output: "No workspace selected", wasSuccessful: false)
            return
        }

        var results: [WorkspaceSearchResult] = []
        for file in files where !file.isDirectory {
            guard let data = try? Data(contentsOf: file.url),
                  let text = String(data: data, encoding: .utf8) else { continue }

            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let lineString = String(line)
                let score = lineScore(query: trimmedQuery, line: lineString, fileName: file.name)
                guard score > 0 else { continue }
                results.append(WorkspaceSearchResult(file: file, lineNumber: index + 1, line: lineString, score: score))
                if results.count >= 40 { break }
            }
            if results.count >= 40 { break }
        }

        searchResults = results.sorted {
            if $0.score == $1.score {
                if $0.file.name == $1.file.name { return $0.lineNumber < $1.lineNumber }
                return $0.file.name.localizedStandardCompare($1.file.name) == .orderedAscending
            }
            return $0.score > $1.score
        }
        actions.insert(WorkspaceAction(title: "Searched workspace", detail: "\"\(trimmedQuery)\" in \(rootURL.path)"), at: 0)
        recordToolCall(
            toolName: "search_workspace",
            input: trimmedQuery,
            output: "\(searchResults.count) ranked results across \(files.count) files",
            wasSuccessful: true
        )
    }

    func summarizeWorkspace() -> String {
        let fileCount = files.count
        let directoryCount = files.filter(\.isDirectory).count
        let textFiles = files.filter { !$0.isDirectory }
        let totalTextBytes = textFiles.reduce(into: 0) { partialResult, file in
            partialResult += (try? Data(contentsOf: file.url).count) ?? 0
        }
        let previewNames = files.prefix(8).map(\.name).joined(separator: ", ")
        let root = rootURL?.lastPathComponent ?? "unknown"
        let summary = """
        Workspace \(root) contains \(fileCount) visible items, including \(directoryCount) folders and \(textFiles.count) files.
        Approximate readable text size: \(totalTextBytes) bytes.
        Sample items: \(previewNames.isEmpty ? "none" : previewNames)
        """
        actions.insert(WorkspaceAction(title: "Summarized workspace", detail: root), at: 0)
        recordToolCall(
            toolName: "summarize_workspace",
            input: root,
            output: summary.replacingOccurrences(of: "\n", with: " "),
            wasSuccessful: true
        )
        return summary
    }

    func proposePatch(instruction: String) {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let selectedFile else { return }

        patchProposals.insert(
            PatchProposal(
                title: trimmed,
                summary: "Drafted a change proposal for \(selectedFile.name)",
                targetPath: selectedFile.url.path,
                proposedChange: """
                Review requested:
                \(trimmed)

                Target file:
                \(selectedFile.url.path)

                Current preview:
                \(selectedFileContents.prefix(1200))

                Proposed change:
                Describe the exact edit before applying it.
                """
            ),
            at: 0
        )
        actions.insert(WorkspaceAction(title: "Proposed patch", detail: "\(trimmed) -> \(selectedFile.url.lastPathComponent)"), at: 0)
        recordToolCall(
            toolName: "propose_patch",
            input: trimmed,
            output: "Drafted patch proposal for \(selectedFile.url.lastPathComponent)",
            wasSuccessful: true
        )
    }

    func setGeneratedPatchDraft(_ draft: String, instruction: String) {
        selectedFileDraft = draft
        selectedFileDraftStatus = "Generated patch draft for \(instruction)."
        actions.insert(WorkspaceAction(title: "Generated patch draft", detail: instruction), at: 0)
        recordToolCall(
            toolName: "draft_patch",
            input: instruction,
            output: "Generated draft for \(selectedFile?.url.lastPathComponent ?? "unknown file")",
            wasSuccessful: true
        )
    }

    func setGeneratedPatchPlan(_ plan: String, instruction: String) {
        guard let selectedFile else { return }
        patchProposals.insert(
            PatchProposal(
                title: instruction,
                summary: "Generated agent plan for \(selectedFile.name)",
                targetPath: selectedFile.url.path,
                proposedChange: plan
            ),
            at: 0
        )
        actions.insert(WorkspaceAction(title: "Generated patch plan", detail: instruction), at: 0)
        recordToolCall(
            toolName: "draft_patch_plan",
            input: instruction,
            output: "Generated reviewable plan for \(selectedFile.url.lastPathComponent)",
            wasSuccessful: true
        )
    }

    func recordToolFailure(toolName: String, input: String, output: String) {
        recordToolCall(toolName: toolName, input: input, output: output, wasSuccessful: false)
    }

    func addTask(title: String, detail: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.insert(WorkspaceTask(title: trimmed, detail: detail), at: 0)
        actions.insert(WorkspaceAction(title: "Added task", detail: trimmed), at: 0)
    }

    func toggleTask(_ task: WorkspaceTask) {
        guard let index = tasks.firstIndex(of: task) else { return }
        tasks[index].isDone.toggle()
        actions.insert(WorkspaceAction(title: tasks[index].isDone ? "Completed task" : "Reopened task", detail: tasks[index].title), at: 0)
    }

    private func lineScore(query: String, line: String, fileName: String) -> Int {
        let queryParts = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !queryParts.isEmpty else { return 0 }
        let loweredLine = line.lowercased()
        let loweredFile = fileName.lowercased()
        var score = 0
        for part in queryParts {
            let loweredPart = part.lowercased()
            if loweredLine.contains(loweredPart) { score += 8 }
            if loweredFile.contains(loweredPart) { score += 4 }
        }
        if loweredLine.localizedCaseInsensitiveContains(query) { score += 12 }
        if loweredFile.localizedCaseInsensitiveContains(query) { score += 6 }
        return score
    }
}
