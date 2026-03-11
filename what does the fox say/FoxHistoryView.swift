import SwiftUI

struct FoxHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: FoxAppViewModel

    @State private var selectedSession: PracticeSessionSummary?
    @State private var pendingDeleteSession: PracticeSessionSummary?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                FoxTheme.historyBackground
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    headerText

                    if viewModel.historySessions.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            "No practice history yet",
                            systemImage: "text.bubble",
                            description: Text("Each completed session will show its transcript, summary, and final feedback here.")
                        )
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        List {
                            ForEach(viewModel.historySessions) { session in
                                HistoryRow(
                                    session: session,
                                    onOpen: { selectedSession = session },
                                    onRetry: {
                                        Task { await viewModel.retrySession(session) }
                                    }
                                )
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 14, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeleteSession = session
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable {
                            await viewModel.refreshHistory()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                if showDeleteConfirmation, let session = pendingDeleteSession {
                    FoxDeletePromptView(
                        title: session.title,
                        onCancel: {
                            showDeleteConfirmation = false
                            pendingDeleteSession = nil
                        },
                        onDelete: {
                            showDeleteConfirmation = false
                            let sessionToDelete = session
                            pendingDeleteSession = nil
                            Task { await viewModel.deleteSession(sessionToDelete) }
                        }
                    )
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FoxSheetPrimaryButton(title: "Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Close history")
                }
            }
            .task {
                await viewModel.refreshHistory()
            }
            .navigationDestination(item: $selectedSession) { session in
                FoxHistoryDetailView(session: session)
                    .environmentObject(viewModel)
            }
        }
        .presentationBackground(.clear)
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Open any session to review the full transcript, a clean summary, and your final feedback note.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.74))
        }
        .padding(.top, 8)
    }
}

private struct HistoryRow: View {
    let session: PracticeSessionSummary
    let onOpen: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Text(session.languagePairLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.68))
                        Spacer()
                        statusView
                    }

                    Text(session.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineSpacing(3)
                        .lineLimit(3)

                    HStack {
                        Text(session.persona.title)
                        Spacer()
                        Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(session.title)
            .accessibilityValue(session.languagePairLabel)
            .accessibilityHint(summaryText)

            if session.status == .failed {
                HStack {
                    Spacer()
                    HistoryActionButton(title: "Retry", tint: FoxTheme.accent, action: onRetry)
                }
            }
        }
        .padding(18)
        .background(FoxTheme.glassCard)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var summaryText: String {
        if session.status == .failed {
            return session.failureReason ?? "This practice session failed before review content could be generated."
        }
        if session.status == .processing {
            if let stage = session.processingStageLabel {
                return "Current stage: \(stage). Your transcript, summary, and feedback are still being prepared."
            }
            return "Your transcript, summary, and feedback are still being prepared."
        }
        return session.summaryText.isEmpty ? "Open this session to view the transcript, summary, and feedback." : session.summaryText
    }

    @ViewBuilder
    private var statusView: some View {
        if session.isUnread {
            statusBadge("NEW", tint: FoxTheme.accent)
        } else if session.status == .processing {
            statusBadge(session.processingStageLabel ?? "Processing", tint: .orange)
        } else if session.status == .failed {
            statusBadge("Failed", tint: FoxTheme.historyDot)
        } else {
            statusBadge("Ready", tint: FoxTheme.readyGreen)
        }
    }

    private func statusBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint.opacity(0.96))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tint.opacity(0.14))
                    .overlay(
                        Capsule()
                            .stroke(tint.opacity(0.22), lineWidth: 1)
                    )
            )
    }
}

private struct HistoryActionButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(tint.opacity(0.18))
                        .overlay(
                            Capsule()
                                .stroke(tint.opacity(0.3), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct FoxHistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: FoxAppViewModel

    let session: PracticeSessionSummary

    @State private var detail: PracticeSessionDetail?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            FoxTheme.historyBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                if let detail {
                    VStack(spacing: 18) {
                        header(detail: detail)
                        if detail.status == .failed {
                            failedCard(detail: detail)
                            failedActions(detail: detail)
                        } else {
                            transcriptCard(detail: detail)
                            summaryCard(detail: detail)
                            feedbackCard(detail: detail)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 20)
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.top, 60)
                } else {
                    ContentUnavailableView("Session unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await viewModel.fetchDetail(session: session)
            detail = fetched
            viewModel.didViewSessionDetail(fetched)
            await viewModel.markSessionRead(fetched)
        } catch {
            debugLog("detail load failed: \(error.localizedDescription)")
        }
    }

    private func header(detail: PracticeSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("\(detail.nativeLanguage.rawValue) -> \(detail.targetLanguage.rawValue)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            HStack {
                Text("Persona: \(detail.persona.title)")
                Spacer()
                Text(detail.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.68))
            if detail.status == .processing, let stage = detail.processingStageLabel {
                Text(stage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FoxTheme.glassCard)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func transcriptCard(detail: PracticeSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcript")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            if detail.transcript.isEmpty {
                Text("No transcript is available for this session yet.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
            } else {
                ForEach(detail.transcript) { segment in
                    TranscriptRow(segment: segment)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FoxTheme.glassCard)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func summaryCard(detail: PracticeSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text(detail.summary.isEmpty ? "No summary is available yet." : detail.summary)
                .font(.body)
                .foregroundStyle(.white.opacity(0.84))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FoxTheme.glassCard)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func feedbackCard(detail: PracticeSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feedback")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text(detail.feedbackOverall.isEmpty ? "No feedback is available yet." : detail.feedbackOverall)
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            FoxTheme.accent.opacity(0.14),
                            Color.clear,
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(FoxTheme.accent.opacity(0.22), lineWidth: 1)
        )
    }

    private func failedCard(detail: PracticeSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session failed")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text(detail.failureReason ?? "This session could not be processed.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.84))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FoxTheme.glassCard)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(FoxTheme.historyDot.opacity(0.32), lineWidth: 1)
        )
    }

    private func failedActions(detail: PracticeSessionDetail) -> some View {
        HStack {
            Button {
                Task { await viewModel.retrySession(session) }
            } label: {
                Text("Retry")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(FoxTheme.accent.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(FoxTheme.accent.opacity(0.34), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct FoxDeletePromptView: View {
    let title: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            FoxTheme.modalBackdrop
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }

            FoxCenteredPromptCard(
                accent: FoxTheme.historyDot,
                symbol: "trash.fill",
                title: "Delete Session?",
                message: "This will permanently remove \"\(title)\" from your history."
            ) {
                HStack(spacing: 12) {
                    promptSecondaryButton(title: "Cancel", action: onCancel)
                    promptPrimaryButton(title: "Delete", tint: FoxTheme.historyDot, action: onDelete)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Delete session confirmation")
    }
}

private struct FoxCenteredPromptCard<Actions: View>: View {
    let accent: Color
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(accent)
                }

                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.82))
                .lineSpacing(4)

            actions
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 28, y: 16)
        )
        .padding(.horizontal, 24)
    }
}

private func promptSecondaryButton(title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .font(.headline.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
}

private func promptPrimaryButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .font(.headline.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            Capsule()
                .fill(tint.opacity(0.86))
                .overlay(
                    Capsule()
                        .stroke(tint.opacity(0.24), lineWidth: 1)
                )
        )
}

private struct TranscriptRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 36)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 7) {
                Text(isUser ? "YOU" : "FOX")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(isUser ? FoxTheme.accentSoft : FoxTheme.accent.opacity(0.9))

                Text(segment.text)
                    .font(.body)
                    .foregroundStyle(isUser ? Color.black.opacity(0.82) : .white)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(bubbleBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(bubbleStroke, lineWidth: 1)
                    )
            }
            .frame(maxWidth: 270, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 36)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUser ? "You said" : "Fox said")
        .accessibilityValue(segment.text)
    }

    private var isUser: Bool {
        segment.speaker == .user
    }

    private var bubbleBackground: AnyShapeStyle {
        if isUser {
            return AnyShapeStyle(Color.white.opacity(0.9))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.24, blue: 0.36).opacity(0.9),
                    Color(red: 0.11, green: 0.14, blue: 0.24).opacity(0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var bubbleStroke: Color {
        isUser ? Color.white.opacity(0.18) : FoxTheme.accent.opacity(0.18)
    }
}
