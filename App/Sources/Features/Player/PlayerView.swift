import SwiftUI

/// Full-screen Now Playing surface.
///
/// Layered top-down: ambient art-extracted wallpaper → hero artwork →
/// editorial metadata → synced transcript → semantic waveform → primary
/// transport → action cluster. Copper accent is reserved for player chrome
/// per UX-15 §9.2.
struct PlayerView: View {

    @Bindable var state: MockPlaybackState
    @Environment(\.dismiss) private var dismiss
    let glassNamespace: Namespace.ID

    @State private var isScrubbing: Bool = false
    @State private var scrubTime: TimeInterval = 0
    @State private var waveformWidth: CGFloat = 320
    @State private var showSpeedSheet: Bool = false
    @State private var showSleepSheet: Bool = false
    @State private var showQueueSheet: Bool = false
    @State private var showShareSheet: Bool = false

    private var copperAccent: Color { state.episode?.primaryArtColor ?? .orange }

    var body: some View {
        ZStack {
            wallpaper
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AppTheme.Spacing.lg) {
                        heroArtwork
                        editorialHeader
                        PlayerTranscriptScrollView(state: state, useGlassCard: true)
                            .frame(minHeight: 240, maxHeight: 320)
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                }

                playbackChrome
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.bottom, AppTheme.Spacing.md)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSpeedSheet) { PlayerSpeedSheet(state: state) }
        .sheet(isPresented: $showSleepSheet) { PlayerSleepTimerSheet(state: state) }
        .sheet(isPresented: $showQueueSheet) { queuePlaceholder }
        .sheet(isPresented: $showShareSheet) { sharePlaceholder }
    }

    // MARK: - Layers

    /// Wallpaper: art-extracted gradient + heavy blur, slow Ken-Burns drift.
    /// Lane 1 / cover-art extraction will replace these solid colors with the
    /// real `UIImage.dominantColors` output.
    private var wallpaper: some View {
        let primary = state.episode?.primaryArtColor ?? .orange
        let secondary = state.episode?.secondaryArtColor ?? .indigo
        return ZStack {
            LinearGradient(
                colors: [primary, secondary, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Color.black.opacity(0.45) // contrast plate
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Minimize player")

            Spacer()

            Text("NOW PLAYING")
                .font(.system(size: 11, design: .rounded).weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.65))

            Spacer()

            Button {
                // Defers to an "More" sheet — UX-03 owns the full options menu.
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.top, AppTheme.Spacing.sm)
    }

    private var heroArtwork: some View {
        let primary = state.episode?.primaryArtColor ?? .orange
        let secondary = state.episode?.secondaryArtColor ?? .indigo
        return ZStack {
            LinearGradient(
                colors: [primary, secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "waveform")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .frame(height: isScrubbing ? 180 : 260)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .scaleEffect(isScrubbing ? 1.04 : 1.0)
        .blur(radius: isScrubbing ? 8 : 0)
        .glassEffectID("player.artwork", in: glassNamespace)
        .animation(AppTheme.Animation.spring, value: isScrubbing)
        .accessibilityHidden(true)
    }

    private var editorialHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let episode = state.episode {
                Text("\(episode.showName.uppercased()) · #\(episode.episodeNumber.map(String.init) ?? "")")
                    .font(.system(size: 11, design: .default).weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.72))
                Text(episode.title)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let chapter = episode.chapterTitle {
                    Text(chapter)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Playback chrome (waveform + transport + actions)

    private var playbackChrome: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            scrubberStack
            PlayerControlsView(
                state: state,
                copperAccent: copperAccent,
                glassNamespace: glassNamespace
            )
            PlayerActionClusterView(
                state: state,
                showSpeedSheet: $showSpeedSheet,
                showSleepSheet: $showSleepSheet,
                showQueueSheet: $showQueueSheet,
                showShareSheet: $showShareSheet,
                copperAccent: copperAccent
            )
        }
    }

    private var scrubberStack: some View {
        VStack(spacing: 8) {
            PlayerWaveformView(
                duration: state.duration,
                currentTime: isScrubbing ? scrubTime : state.currentTime,
                transcript: state.transcript,
                isScrubbing: isScrubbing,
                copperAccent: copperAccent
            )
            .frame(height: isScrubbing ? 220 : 56)
            .animation(AppTheme.Animation.spring, value: isScrubbing)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { waveformWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            waveformWidth = newWidth
                        }
                }
            )
            .gesture(scrubGesture)
            .accessibilityElement()
            .accessibilityLabel("Playback scrubber")
            .accessibilityValue(PlayerTimeFormat.progress(state.currentTime, state.duration))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: state.skipForward(15)
                case .decrement: state.skipBackward(15)
                @unknown default: break
                }
            }

            HStack {
                Text(PlayerTimeFormat.clock(isScrubbing ? scrubTime : state.currentTime))
                Spacer()
                Text(PlayerTimeFormat.clock(state.duration))
            }
            .font(.system(size: 12, design: .monospaced).weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
            .monospacedDigit()
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isScrubbing {
                    isScrubbing = true
                    scrubTime = state.currentTime
                    Haptics.soft()
                }
                let width = max(waveformWidth, 1)
                let dx = value.translation.width / width
                let delta = TimeInterval(dx) * state.duration * 0.4
                scrubTime = max(0, min(state.currentTime + delta, state.duration))
            }
            .onEnded { _ in
                state.seekSnapping(to: scrubTime)
                isScrubbing = false
            }
    }

    private var queuePlaceholder: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Queue")
                    .font(AppTheme.Typography.title)
                Text("Lane 2 owns the queue model. Placeholder for now.")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showQueueSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var sharePlaceholder: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Share")
                    .font(AppTheme.Typography.title)
                Text("Episode link, clip, or Nostr DM. Lane 12 owns the share targets.")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showShareSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
