import AVFoundation
import Core
import SwiftUI
import WhisperShared
#if os(iOS)
import UIKit
#else
import AppKit
import UniformTypeIdentifiers
#endif

@MainActor
private final class RecordingPlayback: ObservableObject {
    @Published var playing = false
    @Published var position = 0.0
    @Published var duration = 0.0
    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    func toggle(_ url: URL) throws {
        if loadedURL != url {
            stop()
            player = try AVAudioPlayer(contentsOf: url)
            loadedURL = url
            duration = player?.duration ?? 0
        }
        if playing { player?.pause(); playing = false }
        else {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            playing = player?.play() ?? false
        }
    }
    func tick() { position = player?.currentTime ?? 0; playing = player?.isPlaying ?? false }
    func seek(_ value: Double) { player?.currentTime = value; position = value }
    func stop() {
        player?.stop(); player = nil; loadedURL = nil; playing = false; position = 0; duration = 0
    }
}

struct AudioAttachmentView: View {
    let entryID: String
    @ObservedObject var store: HistoryStore
    var locale: Locale = .current
    var isRecording = false
    @StateObject private var playback = RecordingPlayback()
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var error: String?
    @State private var confirmDelete = false
    private var repository: RecordingRepository? { store.recordingRepository }
    private var audio: URL? { repository?.savedAudio(entryID) }
    private func t(_ key: AudioCopy.Key) -> String { AudioCopy.text(key, locale: locale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let audio {
                Text(t(.audio)).font(ThemeFont.ui(14, weight: .semibold))
                HStack {
                    ActionButton(title: t(playback.playing ? .pause : .play),
                        systemImage: playback.playing ? "pause.fill" : "play.fill", size: .compact) {
                        do { try playback.toggle(audio) } catch { self.error = t(.exportFailed) }
                    }
                    .accessibilityIdentifier("audio.playPause")
                    ActionButton(title: t(.export), systemImage: "square.and.arrow.up", size: .compact) {
                        export(audio)
                    }.accessibilityIdentifier("audio.exportM4A").disabled(exporting)
                    if exporting { ProgressView() }
                }
                if playback.duration > 0 {
                    Slider(value: Binding(get: { playback.position }, set: { playback.seek($0) }),
                        in: 0...max(0.01, playback.duration)) { Text(t(.position)) }
                    Text("\(Int(playback.position)) / \(Int(playback.duration)) s")
                        .font(ThemeFont.ui(12)).monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                ActionButton(title: t(.remove), systemImage: "trash", role: .destructive, size: .compact) {
                    confirmDelete = true
                }.accessibilityIdentifier("audio.remove").disabled(exporting)
            } else {
                Text(t(.noAudio)).font(ThemeFont.ui(12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .tint(Theme.accent)
        .disabled(isRecording)
        .onChange(of: isRecording) { _, active in if active { playback.stop() } }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in playback.tick() }
        .onChange(of: audio) { _, _ in playback.stop() }
        .onDisappear { playback.stop(); exportTask?.cancel(); cleanExport() }
        .alert(t(.remove), isPresented: $confirmDelete) {
            Button(t(.remove), role: .destructive) {
                playback.stop()
                do { try store.removeRecordingAudio(id: entryID) } catch { self.error = t(.cleanupFailed) }
            }
            Button(t(.cancel), role: .cancel) {}
        } message: { Text(t(.confirmRemove)) }
        .alert(t(.audio), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(t(.close), role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        #if os(iOS)
        .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { cleanExport() } }), onDismiss: cleanExport) {
            if let exportURL { AudioShareSheet(url: exportURL) { cleanExport() } }
        }
        #endif
    }
    private func cleanExport() {
        if let exportURL { repository?.removeExport(exportURL) }
        exportURL = nil
    }
    private func export(_ audio: URL) {
        guard let repository, !exporting else { return }
        exporting = true
        exportTask = Task {
            defer { exporting = false }
            do {
                let url = try await repository.exportM4A(audio)
                if Task.isCancelled { repository.removeExport(url); return }
                #if os(iOS)
                exportURL = url
                #else
                defer { repository.removeExport(url) }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.mpeg4Audio]
                panel.nameFieldStringValue = "WhisperClip.m4a"
                if await panel.begin() == .OK, let destination = panel.url {
                    let staging = destination.deletingLastPathComponent().appendingPathComponent(".whisperclip-" + UUID().uuidString + ".m4a")
                    defer { try? FileManager.default.removeItem(at: staging) }
                    try FileManager.default.copyItem(at: url, to: staging)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
                    } else { try FileManager.default.moveItem(at: staging, to: destination) }
                }
                #endif
            } catch { self.error = t(.exportFailed) }
        }
    }
}

#if os(iOS)
private struct AudioShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in completion() }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

/// Local cleanup failures and legacy orphaned audio remain discoverable until resolved.
struct AudioStorageStatusView: View {
    @ObservedObject var store: HistoryStore
    var locale: Locale = .current
    @State private var found: [URL] = []
    @State private var showingFound = false
    @AppStorage("audio.foundRecordingsOffered") private var offered = false
    private func t(_ key: AudioCopy.Key) -> String { AudioCopy.text(key, locale: locale) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.audioStorageError != nil || store.audioCleanupError != nil {
                Text(t(store.audioCleanupError != nil ? .cleanupFailed : .storageFailed)).foregroundStyle(Theme.textSecondary)
                ActionButton(title: t(.retry), systemImage: "arrow.clockwise", size: .compact) {
                    store.retryAudioCleanup(); store.retryPreparedAudio(); refresh()
                }
            }
            if !found.isEmpty {
                ActionButton(title: t(.found), systemImage: "waveform", size: .compact) { showingFound = true }
            }
        }
        .task { store.retryAudioCleanup(); refresh(); if !found.isEmpty && !offered { showingFound = true; offered = true } }
        .onChange(of: store.revision) { _, _ in refresh() }
        .sheet(isPresented: $showingFound) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(t(.found)).font(ThemeFont.ui(20, weight: .semibold))
                    Text(t(.foundHelp)).foregroundStyle(Theme.textSecondary)
                    ForEach(found, id: \.path) { url in
                        Text(url.lastPathComponent).font(ThemeFont.ui(12)).lineLimit(2)
                        AudioAttachmentView(entryID: url.deletingPathExtension().lastPathComponent, store: store, locale: locale)
                        Divider()
                    }
                    ActionButton(title: t(.close), systemImage: "xmark", size: .compact) { showingFound = false }
                }.padding(20)
            }.frame(minWidth: 280, minHeight: 300).background(Theme.window)
        }
    }
    private func refresh() { found = (try? store.foundRecordings()) ?? [] }
}
