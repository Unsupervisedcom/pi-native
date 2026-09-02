import SwiftUI

struct NewChatStartView: View {
    var selectedProjectName: String?
    var onChooseProject: () -> Void
    var onClearProject: () -> Void
    var onSubmit: (PreparedPrompt) -> Void

    @State private var draft = ""
    @State private var attachments: [ComposerAttachment] = []
    @State private var isHoveringProject = false
    @State private var autosubmitWorkItem: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            Text("What should we work on?")
                .font(.largeTitle.weight(.medium))

            AttachmentComposerShell(
                draft: $draft,
                attachments: $attachments,
                placeholder: "",
                sendDisabled: PromptAttachmentAssembler.prepare(draft: draft, attachments: attachments) == nil,
                isRunning: false,
                onAddAttachments: addAttachments,
                onRemoveAttachment: { id in attachments.removeAll { $0.id == id } },
                onSubmit: submit,
                onStop: {},
                editorHeight: 72
            ) {
                projectPicker
                    .accessibilityIdentifier("newChat.projectPicker")
                Spacer()
            }
            .accessibilityIdentifier("newChat.promptEditor")
            .onChange(of: draft) { _, value in
                let processInfo = ProcessInfo.processInfo
                guard processInfo.environment["PI_NATIVE_AUTOSUBMIT_AFTER_TYPING"] == "1" || processInfo.arguments.contains("--ui-test-autosubmit") else { return }
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                autosubmitWorkItem?.cancel()
                let workItem = DispatchWorkItem { submit() }
                autosubmitWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
            }
            .padding(4)
            .frame(maxWidth: 760, minHeight: 190)

            Spacer()
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var projectPicker: some View {
        Button(action: selectedProjectName == nil ? onChooseProject : onClearProject) {
            HStack(spacing: 6) {
                Image(systemName: selectedProjectName == nil ? "folder" : "folder.fill")
                Text(selectedProjectName ?? "Choose project")
                    .lineLimit(1)
                if selectedProjectName != nil && isHoveringProject {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .accessibilityLabel("Remove project")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.primary.opacity(selectedProjectName == nil ? 0.06 : 0.10), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringProject = $0 }
    }

    private func submit() {
        guard let prepared = PromptAttachmentAssembler.prepare(draft: draft, attachments: attachments) else { return }
        onSubmit(prepared)
        draft = ""
        attachments = []
    }

    private func addAttachments(_ incoming: [ComposerAttachment]) {
        for attachment in incoming {
            if case .fileReference(let file) = attachment.kind,
               attachments.contains(where: { existing in
                   if case .fileReference(let existingFile) = existing.kind {
                       return existingFile.url.standardizedFileURL.path == file.url.standardizedFileURL.path
                   }
                   return false
               }) {
                continue
            }
            attachments.append(attachment)
        }
    }
}
