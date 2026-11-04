# Alexi

Alexi is a local-first personal voice assistant for macOS. The first release keeps personal data on the Mac and sends prompts only to a local model provider.

## MVP scope

- Conversational desktop interface
- Persistent, user-editable personal memory stored locally
- Local LLM connection through Ollama (`http://localhost:11434`)
- Push-to-talk speech recognition and spoken replies through macOS
- Permission-gated access to today's Calendar events and incomplete Reminders
- Friend, DSA Coach, and Wellbeing conversation modes
- Encrypted local memory, check-ins, and DSA progress with keys stored in the macOS Keychain
- Opt-in local morning and evening reminders
- Memory review/edit/delete controls and timed DSA focus sessions
- A custom workspace-agent loop: inspect a selected folder, search and summarize local context, generate a reviewable patch plan, and require human review before a draft can be applied
- Clear separation between conversation, memory, planning, and device actions

Voice input, system integrations, and proactive automation will be introduced only after the assistant is useful and its permission model is in place.

## Run locally

1. Install a local Ollama model, for example: `ollama pull llama3.2`
2. From this directory, run: `./Scripts/launch-app.sh`

The launcher uses Swift Package Manager when it is available and falls back to a direct `swiftc` build when the local Command Line Tools have a SwiftPM manifest mismatch.

Without Ollama, Alexi remains usable for storing and managing local memory, and reports that the local model service is unavailable.

The first use of the microphone asks macOS for Microphone and Speech Recognition permissions. Alexi does not listen until you press the microphone button; use the same button to stop listening.

Use **Voice mode** for hands-free turn taking: Alexi listens, submits your speech after a short pause, speaks its reply, then listens again. Select **End voice mode** to stop it. The **Send** button remains available for editing a transcript before sending.

## Workspace-agent loop

Alexi treats the selected workspace as an explicit tool boundary. It can list, preview, search, and summarize text files in that folder; these actions appear in the activity log. For a requested code change, Alexi asks the chosen model for a patch plan, records the plan for review, and leaves the editable local draft unchanged. A person must review and deliberately apply a draft before any file is written.

Calendar and Reminders are read only until you choose **Create** and explicitly confirm the new event or reminder in Alexi. macOS asks for access the first time Alexi refreshes those sections.

## Companion modes

- **Friend** supports everyday conversation and context-aware check-ins.
- **DSA Coach** tracks a topic, confidence level, weekly problem goal, and solved-problem count. It is instructed to coach with hints before solutions.
- **Wellbeing** supports private reflection and routines. It is not a replacement for licensed mental-health care or emergency services.

Use **Daily check-in** to save a mood, note, and focus for the day. This context remains local and is available to Alexi in future conversations.

Use **Daily routines** to choose a morning check-in and evening reflection time. These are local macOS notifications and can be disabled at any time. Use **Review all memory** to inspect, edit, or forget everything Alexi remembers. A **DSA focus session** records your timed practice notes and updates progress only when you choose to save it.

Run Alexi through `./Scripts/launch-app.sh`, not the raw file inside `.build`. The launcher creates and signs a local `Alexi.app` bundle, then opens a fresh instance so you see the latest build. macOS requires the bundle for notification and privacy permissions.

## Access boundaries

Alexi is sandboxed. It can use only the microphone, Calendar/Reminders, local notifications, and a network client connection to the local Ollama service. It has no permission for browser history, saved passwords, general file-system access, contacts, location, camera, or cloud accounts. Its encryption key is private to Alexi in the macOS Keychain.

## Privacy model

Alexi stores its memory in the app-support directory on this Mac. Memory is always visible, editable, and removable in the app. Future integrations will require explicit per-service permissions and will keep an activity log.
