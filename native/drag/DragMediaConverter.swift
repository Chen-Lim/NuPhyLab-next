import Foundation
import AVFoundation

/// System codecs only; no shell tools, downloads or network services.
enum DragMediaConverter {
    static func convert(_ input: URL, to format: DragFormat, preferences: DragConvertPreferences, control: DragJobControl) throws -> URL {
        let access = input.startAccessingSecurityScopedResource()
        defer { if access { input.stopAccessingSecurityScopedResource() } }
        try DragOutput.validate(input, maxBytes: 4 * 1024 * 1024 * 1024)
        let asset = AVURLAsset(url: input)
        let duration = asset.duration.seconds
        guard duration.isFinite, duration > 0 else { throw DragConvertError.unreadable }
        guard duration <= 7200 else { throw DragConvertError.tooLarge }
        guard !asset.hasProtectedContent else { throw DragConvertError.unsupported }
        let audio = [.m4a, .wav, .aiff].contains(format)
        guard !asset.tracks(withMediaType: audio ? .audio : .video).isEmpty else { throw audio ? DragJobError.noAudio : DragJobError.noVideo }
        try control.check()
        let suffix: String
        switch format { case .video720: suffix = "-720p"; case .video1080: suffix = "-1080p"; default: suffix = "" }
        return try DragOutput.write(input: input, preferences: preferences, suffix: suffix, ext: format.fileExtension) { output in
            if format == .wav || format == .aiff {
                try pcm(asset, output: output, format: format, duration: duration, control: control)
            } else {
                let preset: String
                switch format {
                case .m4a: preset = AVAssetExportPresetAppleM4A
                case .mp4, .mov: preset = AVAssetExportPresetHighestQuality
                case .video720: preset = AVAssetExportPreset1280x720
                case .video1080: preset = AVAssetExportPreset1920x1080
                default: throw DragConvertError.unsupported
                }
                guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else { throw DragConvertError.unsupported }
                let fileType: AVFileType = format == .m4a ? .m4a : (format == .mov ? .mov : .mp4)
                guard exporter.supportedFileTypes.contains(fileType) else { throw DragConvertError.unsupported }
                exporter.outputURL = output; exporter.outputFileType = fileType
                exporter.shouldOptimizeForNetworkUse = !audio
                exporter.metadata = []
                let semaphore = DispatchSemaphore(value: 0)
                exporter.exportAsynchronously { semaphore.signal() }
                let deadline = Date().addingTimeInterval(1800)
                while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
                    if control.cancelled || Date() > deadline {
                        exporter.cancelExport()
                        // Wait until the writer releases its output before removing staging.
                        semaphore.wait()
                        if control.cancelled { throw DragJobError.cancelled }; throw DragJobError.timeout
                    }
                    control.update(Double(exporter.progress))
                }
                try control.check()
                guard exporter.status == .completed else { throw exporter.error ?? DragConvertError.encoding }
            }
            control.update(1); try control.check()
        }
    }
    private static func pcm(_ asset: AVAsset, output: URL, format: DragFormat, duration: Double, control: DragJobControl) throws {
        let reader = try AVAssetReader(asset: asset)
        let tracks = asset.tracks(withMediaType: .audio)
        // Mix all source audio tracks into a predictable stereo 44.1 kHz export.
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        let readerOutput = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw DragConvertError.unsupported }; reader.add(readerOutput)
        let writer = try AVAssetWriter(outputURL: output, fileType: format == .wav ? .wav : .aiff)
        var encoding = settings; encoding[AVLinearPCMIsBigEndianKey] = format == .aiff
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: encoding)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw DragConvertError.unsupported }; writer.add(writerInput)
        guard writer.startWriting(), reader.startReading() else { throw writer.error ?? reader.error ?? DragConvertError.encoding }
        writer.startSession(atSourceTime: .zero)
        let deadline = Date().addingTimeInterval(1800)
        do {
            while reader.status == .reading {
                try control.check()
                guard Date() < deadline else { throw DragJobError.timeout }
                if !writerInput.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw writer.error ?? DragConvertError.encoding }
                    Thread.sleep(forTimeInterval: 0.005); continue
                }
                guard let sample = readerOutput.copyNextSampleBuffer() else { break }
                guard writerInput.append(sample) else { throw writer.error ?? DragConvertError.encoding }
                control.update(CMSampleBufferGetPresentationTimeStamp(sample).seconds / duration)
            }
            guard reader.status == .completed else { throw reader.error ?? DragConvertError.encoding }
            writerInput.markAsFinished()
            let semaphore = DispatchSemaphore(value: 0); writer.finishWriting { semaphore.signal() }
            semaphore.wait()
            guard writer.status == .completed else { throw writer.error ?? DragConvertError.encoding }
            try control.check()
        } catch { reader.cancelReading(); writer.cancelWriting(); throw error }
    }
}

enum DragConverter {
    static func convert(_ urls: [URL], to format: DragFormat, preferences: DragConvertPreferences, control: DragJobControl) throws -> URL {
        _ = try preferences.validated(); try control.check()
        guard DragFileKind.actions(for: urls).contains(format) || (format == .zipEach && DragFileKind.actions(for: urls).contains(.zip)) else { throw DragConvertError.unsupported }
        switch format {
        case .jpg, .png, .webp, .heic, .tiff, .small:
            let output = try DragImageConverter.convert(urls[0], to: format, preferences: preferences, check: control.check)
            control.update(1); return output
        case .zip, .zipEach, .zipFast, .tarGz, .extract:
            return try DragArchiveConverter.convert(urls, to: format, preferences: preferences, control: control)
        case .imagesPDF, .pdfPNG, .pdfJPG, .splitPDF, .mergePDF:
            return try DragDocumentConverter.convert(urls, to: format, preferences: preferences, control: control)
        default: return try DragMediaConverter.convert(urls[0], to: format, preferences: preferences, control: control)
        }
    }
}
