import AVFoundation
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class VoiceService: NSObject, AVSpeechSynthesizerDelegate {
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?

    var transcript = ""
    var finalizedTranscript: String?
    var isListening = false
    var isVoiceModeEnabled = false
    var isSpeaking = false
    var errorMessage: String?
    var voiceStatus = "Voice mode is off"

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func startVoiceMode() async {
        isVoiceModeEnabled = true
        voiceStatus = "Starting microphone…"
        await startListening()
    }

    func stopVoiceMode() {
        isVoiceModeEnabled = false
        silenceTask?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        stopListening()
        voiceStatus = "Voice mode is off"
    }

    func startListening() async {
        errorMessage = nil

        guard await hasPermissions() else {
            errorMessage = "Allow Microphone and Speech Recognition access in System Settings to use voice input."
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is unavailable right now."
            return
        }

        stopListening()
        transcript = ""
        finalizedTranscript = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            errorMessage = "No usable microphone input is available. Check your Mac's input device in System Settings."
            return
        }
        Self.installTap(on: inputNode, request: request, format: recordingFormat)

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    let updatedTranscript = result.bestTranscription.formattedString
                    if self?.transcript != updatedTranscript {
                        self?.transcript = updatedTranscript
                        self?.scheduleSilenceDetection()
                    }
                    if result.isFinal {
                        self?.finishRecognition()
                    }
                }
                if error != nil, self?.isListening == true {
                    self?.errorMessage = "I couldn't understand that. Please try again."
                    self?.stopListening()
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            voiceStatus = "Listening… pause when you finish speaking"
        } catch {
            inputNode.removeTap(onBus: 0)
            errorMessage = "I couldn't start the microphone: \(error.localizedDescription)"
        }
    }

    func stopListening() {
        guard isListening || recognitionRequest != nil else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    func submitCurrentTranscript() {
        silenceTask?.cancel()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            stopListening()
            return
        }
        stopListening()
        voiceStatus = "Sending your message…"
        finalizedTranscript = transcript
    }

    func clearFinalizedTranscript() {
        finalizedTranscript = nil
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = true
        voiceStatus = "Alexi is speaking…"
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }

    private func hasPermissions() async -> Bool {
        let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        let speechStatus = await Self.requestSpeechAuthorization()
        return microphoneGranted && speechStatus == .authorized
    }

    private func finishRecognition() {
        guard isListening else { return }
        submitCurrentTranscript()
    }

    private func scheduleSilenceDetection() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.finishRecognition()
        }
    }

    func interruptAndListen() {
        guard isVoiceModeEnabled, isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        voiceStatus = "Interrupted. Listening…"
        Task {
            await startListening()
        }
    }

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    nonisolated private static func installTap(on inputNode: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest, format: AVAudioFormat) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            guard self.isVoiceModeEnabled else { return }
            self.voiceStatus = "Listening for your next message…"
            if !self.isListening {
                await self.startListening()
            }
        }
    }
}
