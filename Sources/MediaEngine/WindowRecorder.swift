import AppKit
@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit
import ProjectCore

public struct CaptureWindow: Identifiable, @unchecked Sendable {
    public let window: SCWindow
    public var id: CGWindowID { window.windowID }
    public var title: String { "\(window.owningApplication?.applicationName ?? "App") — \(window.title ?? "Untitled window")" }
}

/// Capture callbacks share a serial queue. MainActor owns recording lifecycle and UI state.
@MainActor public final class WindowRecorder: NSObject {
    private var stream: SCStream?
    private var recording: SCRecordingOutput?
    private var tracker: CursorTracker?
    private var startWaiter: CheckedContinuation<Void, Error>?
    private var finishWaiter: CheckedContinuation<Void, Error>?
    private var completed = false
    private var recordingError: Error?
    private var sessionID = UUID()
    public private(set) var isRecording = false
    public var onFailure: ((Error) -> Void)?
    public init(onFailure: ((Error) -> Void)? = nil) { self.onFailure = onFailure; super.init() }

    public static func windows() async throws -> [CaptureWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows.filter {
            $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 100 && $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
        }.map(CaptureWindow.init).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func start(window: CaptureWindow, destination: URL, systemAudio: Bool, microphone: Bool) async throws {
        guard stream == nil else { throw ProjectError("A recording is already active.") }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ProjectError("Recording destination already exists.") }
        if microphone {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else { throw ProjectError("Microphone access is disabled in System Settings.") }
        }
        let filter = SCContentFilter(desktopIndependentWindow: window.window)
        let configuration = SCStreamConfiguration()
        let size = filter.contentRect.size
        let pixelScale = Double(filter.pointPixelScale)
        let bound = min(1, min(3840 / max(1, size.width * pixelScale), 2160 / max(1, size.height * pixelScale)))
        configuration.width = max(2, Int(size.width * pixelScale * bound) / 2 * 2)
        configuration.height = max(2, Int(size.height * pixelScale * bound) / 2 * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        // Cursor telemetry is rendered later so styling and zooms remain editable.
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.capturesAudio = systemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = microphone
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        configuration.queueDepth = 5
        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = destination
        outputConfiguration.videoCodecType = .h264
        outputConfiguration.outputFileType = .mp4
        let recording = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let tracker = CursorTracker(windowID: window.id, initialBounds: window.window.frame)
        try stream.addStreamOutput(tracker, type: .screen, sampleHandlerQueue: tracker.queue)
        try stream.addRecordingOutput(recording)
        self.stream = stream; self.recording = recording; self.tracker = tracker
        sessionID = UUID(); let currentSession = sessionID
        completed = false; recordingError = nil
        do {
            try await withCheckedThrowingContinuation { continuation in
                startWaiter = continuation
                Task {
                    do { try await stream.startCapture() }
                    catch { if sessionID == currentSession { fail(error) } }
                }
                Task {
                    try? await Task.sleep(for: .seconds(15))
                    if sessionID == currentSession, startWaiter != nil { fail(ProjectError("Recording did not start. Check Screen Recording permission in System Settings.")) }
                }
            }
            isRecording = true
        } catch {
            try? await stream.stopCapture()
            tracker.stop()
            self.stream = nil; self.recording = nil; self.tracker = nil
            throw error
        }
    }

    public func stop() async throws -> [CursorSample] {
        guard let stream else { throw ProjectError("No active recording.") }
        let currentSession = sessionID
        defer { tracker?.stop(); self.stream = nil; recording = nil; tracker = nil; isRecording = false }
        try await stream.stopCapture()
        if let recordingError { throw recordingError }
        if !completed {
            try await withCheckedThrowingContinuation { continuation in
                finishWaiter = continuation
                Task {
                    try? await Task.sleep(for: .seconds(15))
                    if sessionID == currentSession, finishWaiter != nil { fail(ProjectError("Timed out while finalizing the recording.")) }
                }
            }
        }
        return tracker?.samples() ?? []
    }

    private func fail(_ error: Error) {
        recordingError = error
        startWaiter?.resume(throwing: error); startWaiter = nil
        finishWaiter?.resume(throwing: error); finishWaiter = nil
        isRecording = false
        onFailure?(error)
    }
}

extension WindowRecorder: SCRecordingOutputDelegate, SCStreamDelegate {
    nonisolated public func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            guard recording === recordingOutput else { return }
            startWaiter?.resume(); startWaiter = nil
        }
    }
    nonisolated public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            guard recording === recordingOutput else { return }
            completed = true; finishWaiter?.resume(); finishWaiter = nil
        }
    }
    nonisolated public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            guard recording === recordingOutput else { return }
            fail(error)
        }
    }
    nonisolated public func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            fail(error)
        }
    }
}

private final class CursorTracker: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "takelet.capture.cursor")
    private let windowID: CGWindowID
    private var bounds: CGRect
    private var firstPTS: CMTime?
    private var streamClock: CMClock?
    private var fallbackClockStart: CMTime?
    private var timer: DispatchSourceTimer?
    private var finished = false
    private var visibleContent = false
    private var values: [CursorSample] = []
    init(windowID: CGWindowID, initialBounds: CGRect) { self.windowID = windowID; bounds = initialBounds }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw), !finished else { return }
        if status == .blank || status == .suspended || status == .stopped {
            visibleContent = false
            if let time = currentTime() { sample(at: time) }
            return
        }
        guard status == .complete || status == .idle else { return }
        if status == .complete { visibleContent = true }
        // Both consumers use the same stream clock. SCRecordingOutput doesn't expose its
        // first encoded PTS, so the first complete screen buffer is our zero-time anchor.
        guard firstPTS == nil, status == .complete else { return }
        firstPTS = sampleBuffer.presentationTimeStamp
        streamClock = stream.synchronizationClock
        fallbackClockStart = CMClockGetTime(CMClockGetHostTimeClock())
        sample(at: 0)
        // A clean static frame need not be delivered again when only the cursor moves.
        // Poll separately so mouse telemetry continues through SCFrameStatus.idle.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(33), repeating: .nanoseconds(33_333_333), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self, !finished, let time = currentTime() else { return }
            sample(at: time)
        }
        self.timer = timer; timer.resume()
    }

    private func currentTime() -> Double? {
        guard let firstPTS else { return nil }
        if let streamClock { return (CMClockGetTime(streamClock) - firstPTS).seconds }
        guard let fallbackClockStart else { return nil }
        return (CMClockGetTime(CMClockGetHostTimeClock()) - fallbackClockStart).seconds
    }

    private func sample(at time: Double) {
        guard time.isFinite, time >= 0, time > (values.last?.time ?? -1), values.count < 40_000 else { return }
        // Quartz window bounds and CGEvent locations share a top-left display coordinate space.
        let hasWindow: Bool
        if let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
           let rect = info.first?[kCGWindowBounds as String] as? [String: Any],
           let current = CGRect(dictionaryRepresentation: rect as CFDictionary) { bounds = current; hasWindow = true }
        else { hasWindow = false }
        guard bounds.width > 0, bounds.height > 0, let location = CGEvent(source: nil)?.location else { return }
        values.append(CursorSample(time: time, x: (location.x - bounds.minX) / bounds.width, y: (location.y - bounds.minY) / bounds.height,
                                   visible: visibleContent && hasWindow && bounds.contains(location), pressed: CGEventSource.buttonState(.combinedSessionState, button: .left)))
    }
    func samples() -> [CursorSample] { queue.sync { values } }
    func stop() { queue.sync { finished = true; timer?.cancel(); timer = nil } }
    deinit { timer?.cancel() }
}
