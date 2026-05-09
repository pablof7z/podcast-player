import SwiftUI

// MARK: - HomeAddItemRow

/// Inline add row shown in HomeView when the user taps "+".
///
/// Contains its own layout constants and commit action so HomeView doesn't need
/// to duplicate them. Includes a microphone button for voice-to-text input via
/// `VoiceItemService`.
///
/// ## Natural-language due-date detection
/// As the user types, `NaturalDateParser` is consulted on every draft change.
/// When a date phrase is found (e.g. "buy milk tomorrow", "dentist Friday 3pm")
/// a compact date-pill appears below the text field showing the extracted date.
/// On commit the date is stripped from the title and saved as `dueAt`. The pill
/// can be dismissed by tapping the × to opt out of the automatic date.
struct HomeAddItemRow: View {

    // MARK: - Layout constants

    private enum Layout {
        static let circleSize: CGFloat = 22
        static let micIconSize: CGFloat = 18
        static let stopIconSize: CGFloat = 12
    }

    // MARK: - Environment / bindings

    @Environment(AppStateStore.self) private var store

    @Binding var draft: String
    @Binding var showAddItem: Bool
    @FocusState.Binding var isFocused: Bool

    // MARK: - State

    @State private var voice = VoiceItemService()
    /// Tracks whether the current draft text was transcribed via voice (vs. typed).
    @State private var draftFromVoice = false
    /// Result of the last `NaturalDateParser.parse(_:)` call on `draft`.
    /// Non-nil when a recognisable date phrase is present in the draft.
    @State private var parsedDate: NaturalDateParser.ParseResult?
    /// When `true` the user has dismissed the pill for the current draft text,
    /// opting out of automatic due-date detection until the draft changes again.
    @State private var datePillDismissed = false

    // MARK: - Derived

    /// The parsed date pill should be visible when a date is detected and the
    /// user has not explicitly dismissed it for this draft.
    private var showDatePill: Bool {
        parsedDate != nil && !datePillDismissed
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "circle")
                    .font(.system(size: Layout.circleSize))
                    .foregroundStyle(.tertiary)
                    .frame(width: AppTheme.Layout.iconSm, height: AppTheme.Layout.iconSm)

                TextField("New item…", text: $draft)
                    .focused($isFocused)
                    .onSubmit { commit() }
                    .submitLabel(.done)
                    .disabled(voice.phase == .recording)
                    .onChange(of: draft) { _, newValue in
                        // If the user edits the transcribed text, treat it as manual.
                        if voice.phase == .idle { draftFromVoice = false }
                        updateDatePill(for: newValue)
                    }

                trailingButton
                    .animation(AppTheme.Animation.springFast, value: voice.phase == .recording)
                    .animation(AppTheme.Animation.springFast, value: draft.isBlank)
            }

            if showDatePill, let result = parsedDate {
                DetectedDatePill(date: result.date) {
                    withAnimation(AppTheme.Animation.springFast) {
                        datePillDismissed = true
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.leading, AppTheme.Layout.iconSm + AppTheme.Spacing.sm)
                .animation(AppTheme.Animation.spring, value: showDatePill)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .onChange(of: voice.phase) { _, newPhase in
            if case .failed = newPhase {
                // Restore text-field focus on error so the user can type instead.
                isFocused = true
            }
        }
    }

    // MARK: - Trailing button (mic / stop / submit)

    @ViewBuilder
    private var trailingButton: some View {
        if voice.phase == .recording {
            stopMicButton
                .transition(.scale.combined(with: .opacity))
        } else if !draft.isBlank {
            submitButton
                .transition(.scale.combined(with: .opacity))
        } else {
            micButton
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var submitButton: some View {
        Button(action: commit) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.Gradients.agentAccent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save item")
    }

    private var micButton: some View {
        Button {
            Task { await startRecording() }
        } label: {
            Image(systemName: "mic")
                .font(.system(size: Layout.micIconSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: AppTheme.Layout.iconSm, height: AppTheme.Layout.iconSm)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record voice input")
    }

    private var stopMicButton: some View {
        Button {
            voice.stop()
            isFocused = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: AppTheme.Layout.iconSm, height: AppTheme.Layout.iconSm)
                Image(systemName: "stop.fill")
                    .font(.system(size: Layout.stopIconSize, weight: .bold))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop recording")
    }

    // MARK: - Natural-date parsing

    /// Re-runs the parser whenever the draft text changes. Resets the dismissed
    /// flag whenever new text arrives so a fresh parse can show a new pill.
    private func updateDatePill(for text: String) {
        let result = NaturalDateParser.parse(text)
        if result != parsedDate {
            // New parse result (including nil → nil no-op) — reset dismiss flag
            // only when the result actually changed so typing within an existing
            // detection doesn't keep flashing the pill.
            datePillDismissed = false
        }
        parsedDate = result
    }

    // MARK: - Actions

    private func startRecording() async {
        isFocused = false
        draft = ""
        draftFromVoice = true
        await voice.start { [self] text in
            draft = text
        }
    }

    private func commit() {
        if voice.phase == .recording { voice.stop() }
        let trimmed = draft.trimmed
        guard !trimmed.isEmpty else { return }
        let source: ItemSource = draftFromVoice ? .voice : .manual

        // Use the auto-detected due date when available and not dismissed.
        if showDatePill, let result = parsedDate {
            let item = store.addItem(title: result.cleanedTitle, source: source)
            store.setDueDate(item.id, date: result.date)
        } else {
            store.addItem(title: trimmed, source: source)
        }

        Haptics.success()
        draft = ""
        draftFromVoice = false
        parsedDate = nil
        datePillDismissed = false
        withAnimation(AppTheme.Animation.springFast) {
            showAddItem = false
        }
    }

    // MARK: - DetectedDatePill

    /// Compact inline chip shown below the add-item text field when a due date is
    /// detected in the draft text. Displays the formatted date and a dismiss button.
    private struct DetectedDatePill: View {

        private enum PillLayout {
            static let dismissIconSize: CGFloat = 9
        }

        let date: Date
        let onDismiss: () -> Void

    private var formatted: String {
        // Show time only when NSDataDetector returned a specific time-of-day
        // (i.e. the components are not exactly midnight).
        let cal = Calendar.current
        let isMidnight = cal.component(.hour, from: date) == 0 &&
                         cal.component(.minute, from: date) == 0
        return isMidnight ? date.relativeDueLabel : date.shortDateTime
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "calendar.badge.clock")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Due \(formatted)")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(Color.accentColor)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: PillLayout.dismissIconSize, weight: .bold))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove detected date")
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(Color.accentColor.opacity(0.10), in: Capsule())
    }
    }
}
