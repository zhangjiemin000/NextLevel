//
//  NextLevelSession.swift
//  NextLevel (http://nextlevel.engineering/)
//
//  Copyright (c) 2016-present patrick piemonte (http://patrickpiemonte.com)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import AVFoundation

// MARK: - NextLevelSession

/// NextLevelSession, a powerful object for managing and editing a set of recorded media clips.
public class NextLevelSession {

    /// Output directory for a session.
    public var outputDirectory: String

    /// Output file type for a session, see AVMediaFormat.h for supported types.
    public var fileType: AVFileType = .mp4

    /// Output file extension for a session, see AVMediaFormat.h for supported extensions.
    public var fileExtension: String = "mp4"

    /// Unique identifier for a session.
    public var identifier: UUID {
        get {
            return self._identifier
        }
    }

    /// Creation date for a session.
    public var date: Date {
        get {
            return self._date
        }
    }

    /// Creates a URL for session output, otherwise nil
    public var url: URL? {
        get {
            let filename = "\(self.identifier.uuidString)-NL-merged.\(self.fileExtension)"
            if let url = NextLevelClip.clipURL(withFilename: filename, directoryPath: self.outputDirectory) {
                return url
            } else {
                return nil
            }
        }
    }

    public var isVideoSetup: Bool {
        get {
            return self._videoInput != nil
        }
    }

    /// Checks if the session is setup for recording video
    public var isVideoReady: Bool {
        get {
            return self._videoInput?.isReadyForMoreMediaData ?? false
        }
    }

    public var isAudioSetup: Bool {
        get {
            return self._audioInput != nil
        }
    }

    /// Checks if the session is setup for recording audio
    public var isAudioReady: Bool {
        get {
            return self._audioInput?.isReadyForMoreMediaData ?? false
        }
    }

    /// Recorded clips for the session.
    public var clips: [NextLevelClip] {
        get {
            return self._clips
        }
    }

    /// Duration of a session, the sum of all recorded clips.
    public var totalDuration: CMTime {
        get {
            return CMTimeAdd(self._totalDuration, self._currentClipDuration)
        }
    }

    /// Checks if the session's asset writer is ready for data.
    public var isReady: Bool {
        get {
            return self._writer != nil
        }
    }

    /// True if the current clip recording has been started.
    public var currentClipHasStarted: Bool {
        get {
            return self._currentClipHasStarted
        }
    }

    /// Duration of the current clip.
    public var currentClipDuration: CMTime {
        get {
            return self._currentClipDuration
        }
    }

    /// Checks if the current clip has video.
    public var currentClipHasVideo: Bool {
        get {
            return self._currentClipHasVideo
        }
    }

    /// Checks if the current clip has audio.
    public var currentClipHasAudio: Bool {
        get {
            return self._currentClipHasAudio
        }
    }

    /// `AVAsset` of the session.
    public var asset: AVAsset? {
        get {
            var asset: AVAsset? = nil
            self.executeClosureSyncOnSessionQueueIfNecessary {
                if self._clips.count == 1 {
                    //如果只有一个片段
                    asset = self._clips.first?.asset
                } else {
                    //如果有多个片段
                    let composition: AVMutableComposition = AVMutableComposition()
                    self.appendClips(toComposition: composition)
                    asset = composition
                }
            }
            return asset
        }
    }

    /// Shared pool where by which all media is allocated.
    public var pixelBufferPool: CVPixelBufferPool? {
        get {
            return self._pixelBufferAdapter?.pixelBufferPool
        }
    }

    // MARK: - private instance vars

    internal var _identifier: UUID
    internal var _date: Date

    internal var _totalDuration: CMTime = .zero
    internal var _clips: [NextLevelClip] = []
    internal var _clipFilenameCount: Int = 0

    internal var _writer: AVAssetWriter?
    ///video input 是对资源的写入对象
    internal var _videoInput: AVAssetWriterInput?
    internal var _audioInput: AVAssetWriterInput?
    //相对于Audio，VideoBuffer可以用BufferAdpter中转一下，这样更加有效率，并且Adaptor类似于一个缓冲池
    internal var _pixelBufferAdapter: AVAssetWriterInputPixelBufferAdaptor?

    internal var _videoConfiguration: NextLevelVideoConfiguration?
    internal var _audioConfiguration: NextLevelAudioConfiguration?

    internal var _audioQueue: DispatchQueue
    internal var _sessionQueue: DispatchQueue
    internal var _sessionQueueKey: DispatchSpecificKey<()>

    internal var _currentClipDuration: CMTime = .zero
    internal var _currentClipHasAudio: Bool = false
    internal var _currentClipHasVideo: Bool = false

    internal var _currentClipHasStarted: Bool = false
    internal var _timeOffset: CMTime = CMTime.invalid
    internal var _startTimestamp: CMTime = CMTime.invalid
    internal var _lastAudioTimestamp: CMTime = CMTime.invalid
    internal var _lastVideoTimestamp: CMTime = CMTime.invalid

    internal var _skippedAudioBuffers: [CMSampleBuffer] = []

    private let NextLevelSessionAudioQueueIdentifier = "engineering.NextLevel.session.audioQueue"
    private let NextLevelSessionQueueIdentifier = "engineering.NextLevel.sessionQueue"
    private let NextLevelSessionSpecificKey = DispatchSpecificKey<()>()

    // MARK: - object lifecycle

    /// Initialize using a specific dispatch queue.
    ///
    /// - Parameters:
    ///   - queue: Queue for a session operations
    ///   - queueKey: Key for re-calling the session queue from the system
    public convenience init(queue: DispatchQueue, queueKey: DispatchSpecificKey<()>) {
        self.init()
        self._sessionQueue = queue
        self._sessionQueueKey = queueKey
    }

    /// Initializer.
    public init() {
        self._identifier = UUID()
        self._date = Date()
        self.outputDirectory = NSTemporaryDirectory()

        self._audioQueue = DispatchQueue(label: NextLevelSessionAudioQueueIdentifier)

        // should always use init(queue:queueKey:), but this may be good for the future
        self._sessionQueue = DispatchQueue(label: NextLevelSessionQueueIdentifier)
        self._sessionQueue.setSpecific(key: NextLevelSessionSpecificKey, value: ())
        self._sessionQueueKey = NextLevelSessionSpecificKey
    }

    deinit {
        self._writer = nil
        self._videoInput = nil
        self._audioInput = nil
        self._pixelBufferAdapter = nil

        self._videoConfiguration = nil
        self._audioConfiguration = nil
    }

}

// MARK: - setup

extension NextLevelSession {

    /// Prepares a session for recording video.
    /// 设置一些Video的写入配置
    /// - Parameters:
    ///   - settings: AVFoundation video settings dictionary
    ///   - configuration: Video configuration for video output
    ///   - formatDescription: sample buffer format description
    /// - Returns: True when setup completes successfully
    public func setupVideo(withSettings settings: [String: Any]?, configuration: NextLevelVideoConfiguration, formatDescription: CMFormatDescription? = nil) -> Bool {
        if let formatDescription = formatDescription {
            self._videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: settings, sourceFormatHint: formatDescription)
        } else {
            if let _ = settings?[AVVideoCodecKey],
               let _ = settings?[AVVideoWidthKey],
               let _ = settings?[AVVideoHeightKey] {
                //初始化资源写入
                self._videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: settings)
            } else {
                print("NextLevelSession, configuration failure for video output")
                self._videoInput = nil
                return false
            }
        }
        //如果存在Video写入的情况
        if let videoInput = self._videoInput {
            videoInput.expectsMediaDataInRealTime = true
            videoInput.transform = configuration.transform
            self._videoConfiguration = configuration

            var pixelBufferAttri: [String: Any] = [String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]

            if let formatDescription = formatDescription {
                let videoDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                pixelBufferAttri[String(kCVPixelBufferWidthKey)] = Float(videoDimensions.width)
                pixelBufferAttri[String(kCVPixelBufferHeightKey)] = Float(videoDimensions.height)
            } else if let width = settings?[AVVideoWidthKey],
                      let height = settings?[AVVideoHeightKey] {
                pixelBufferAttri[String(kCVPixelBufferWidthKey)] = width
                pixelBufferAttri[String(kCVPixelBufferHeightKey)] = height
            }
            //这个是写入视频的适配器?
            self._pixelBufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: pixelBufferAttri)
        }
        return self.isVideoSetup
    }

    /// Prepares a session for recording audio.
    /// 设置存储Audio的配置
    /// - Parameters:
    ///   - settings: AVFoundation audio settings dictionary
    ///   - configuration: Audio configuration for audio output
    ///   - formatDescription: sample buffer format description
    /// - Returns: True when setup completes successfully
    public func setupAudio(withSettings settings: [String: Any]?, configuration: NextLevelAudioConfiguration, formatDescription: CMFormatDescription) -> Bool {
        //初始化audioInput
        self._audioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: settings, sourceFormatHint: formatDescription)
        if let audioInput = self._audioInput {
            audioInput.expectsMediaDataInRealTime = true
            self._audioConfiguration = configuration
        }
        return self.isAudioSetup
    }

    ///
    /// 创建Writer
    /// 需要输入VideoInput、AudioInput， 不需要Output，初始化Writer时，自动链接了文件目录
    internal func setupWriter() {
        guard let url = self.nextFileURL() else {
            return
        }

        do {
            //初始化AssetWriter
            self._writer = try AVAssetWriter(url: url, fileType: self.fileType)
            if let writer = self._writer {
                writer.shouldOptimizeForNetworkUse = true
                //生成metadata
                writer.metadata = NextLevel.assetWriterMetadata()
                //writer 也要加入videoInput
                if let videoInput = self._videoInput {
                    if writer.canAdd(videoInput) {
                        writer.add(videoInput)
                    } else {
                        print("NextLevel, could not add video input to session")
                    }
                }

                if let audioInput = self._audioInput {
                    if writer.canAdd(audioInput) {
                        writer.add(audioInput)
                    } else {
                        print("NextLevel, could not add audio input to session")
                    }
                }

                if writer.startWriting() {
                    self._timeOffset = CMTime.zero
                    self._startTimestamp = CMTime.invalid
                    self._currentClipHasStarted = true
                } else {
                    print("NextLevel, writer encountered an error \(String(describing: writer.error))")
                    self._writer = nil
                }
            }
        } catch {
            print("NextLevel could not create asset writer")
        }
    }

    internal func destroyWriter() {
        self._writer = nil
        self._currentClipHasStarted = false
        self._timeOffset = CMTime.zero
        self._startTimestamp = CMTime.invalid
        self._currentClipDuration = CMTime.zero
        self._currentClipHasVideo = false
        self._currentClipHasAudio = false
    }
}

// MARK: - recording

extension NextLevelSession {

    /// Completion handler type for appending a sample buffer
    public typealias NextLevelSessionAppendSampleBufferCompletionHandler = (_: Bool) -> Void

    /// Append video sample buffer frames to a session for recording.
    /// 这个是包含音频和视频的CMBuffer
    /// - Parameters:
    ///   - sampleBuffer: Sample buffer input to be appended, unless an image buffer is also provided
    ///   - imageBuffer: Optional image buffer input for writing a custom buffer
    ///   - minFrameDuration: Current active minimum frame duration
    ///   - completionHandler: Handler when a frame appending operation completes or fails
    public func appendVideo(withSampleBuffer sampleBuffer: CMSampleBuffer, customImageBuffer: CVPixelBuffer?, minFrameDuration: CMTime, completionHandler: NextLevelSessionAppendSampleBufferCompletionHandler) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        self.startSessionIfNecessary(timestamp: timestamp)  //处理时间戳

        var frameDuration = minFrameDuration
        let offsetBufferTimestamp = CMTimeSubtract(timestamp, self._timeOffset)

        if let timeScale = self._videoConfiguration?.timescale,
           timeScale != 1.0 {
            let scaledDuration = CMTimeMultiplyByFloat64(minFrameDuration, multiplier: timeScale)
            if self._currentClipDuration.value > 0 {
                self._timeOffset = CMTimeAdd(self._timeOffset, CMTimeSubtract(minFrameDuration, scaledDuration))
            }
            frameDuration = scaledDuration
        }

        if let videoInput = self._videoInput,
           let pixelBufferAdapter = self._pixelBufferAdapter,
           videoInput.isReadyForMoreMediaData {

            var bufferToProcess: CVPixelBuffer? = nil
            if let customImageBuffer = customImageBuffer {
                bufferToProcess = customImageBuffer
            } else {
                bufferToProcess = CMSampleBufferGetImageBuffer(sampleBuffer)
            }

            if let bufferToProcess = bufferToProcess,
               pixelBufferAdapter.append(bufferToProcess, withPresentationTime: offsetBufferTimestamp) {
                self._currentClipDuration = CMTimeSubtract(CMTimeAdd(offsetBufferTimestamp, frameDuration), self._startTimestamp)
                self._lastVideoTimestamp = timestamp
                self._currentClipHasVideo = true
                completionHandler(true)
                return
            }
        }
        completionHandler(false)
    }

    // Beta: appendVideo(withPixelBuffer:customImageBuffer:timestamp:minFrameDuration:completionHandler:) needs to be tested

    /// Append video pixel buffer frames to a session for recording.
    /// 将Video的帧加入到文件中，视频帧的存放是通过时间戳+pixelBuffer来的
    /// - Parameters:
    ///   - sampleBuffer: Sample buffer input to be appended, unless an image buffer is also provided
    ///   - customImageBuffer: Optional image buffer input for writing a custom buffer
    ///   - minFrameDuration: Current active minimum frame duration
    ///   - completionHandler: Handler when a frame appending operation completes or fails
    public func appendVideo(withPixelBuffer pixelBuffer: CVPixelBuffer, customImageBuffer: CVPixelBuffer?, timestamp: TimeInterval, minFrameDuration: CMTime, completionHandler: NextLevelSessionAppendSampleBufferCompletionHandler) {
        //创建时间戳
        let timestamp = CMTime(seconds: timestamp, preferredTimescale: minFrameDuration.timescale)
        //AVAssetWriter的Session，如果需要开始，就开始
        self.startSessionIfNecessary(timestamp: timestamp)
        //获取当前的duration
        var frameDuration = minFrameDuration
        //获取两个时间戳之间的差距，正常来说，timeOffet 通常为0
        let offsetBufferTimestamp = CMTimeSubtract(timestamp, self._timeOffset)
        //如果速度不是1
        // 这里的timeScale是针对当前帧的速度，timeScale可以控制这一帧需要多长的时间，而传入的timestamp是真实的时间戳，这样，转存到文件中
        //这个timestamp就不能直接代表帧的绝对时间了，所以，timeOffset就是起到这种作用
        //timeOffset就是指当前时间戳与实际时间戳偏移的距离，这里就可以起到快进或者慢放的效果
        if let timeScale = self._videoConfiguration?.timescale,
           timeScale != 1.0 {
            //这个是转换得到的最低帧速度
            let scaledDuration = CMTimeMultiplyByFloat64(minFrameDuration, multiplier: timeScale)
            if self._currentClipDuration.value > 0 {
                //如果当前拍摄的时间不为0，则还要计算当前的真实timeOffet的
                self._timeOffset = CMTimeAdd(self._timeOffset, CMTimeSubtract(minFrameDuration, scaledDuration))
            }
            frameDuration = scaledDuration
        }

        if let videoInput = self._videoInput,
           let pixelBufferAdapter = self._pixelBufferAdapter,
           videoInput.isReadyForMoreMediaData {

            var bufferToProcess: CVPixelBuffer? = nil
            if let customImageBuffer = customImageBuffer {
                bufferToProcess = customImageBuffer
            } else {
                bufferToProcess = pixelBuffer
            }

            if let bufferToProcess = bufferToProcess,
               //写入文件，并标记视频时间戳，这里的时间戳是绝对时间戳
               pixelBufferAdapter.append(bufferToProcess, withPresentationTime: offsetBufferTimestamp) {
                //视频的时长
                self._currentClipDuration = CMTimeSubtract(CMTimeAdd(offsetBufferTimestamp, frameDuration), self._startTimestamp)
                self._lastVideoTimestamp = timestamp
                self._currentClipHasVideo = true
                completionHandler(true)
                return
            }
        }
        completionHandler(false)
    }

    /// Append audio sample buffer to a session for recording.
    /// 放入音频,实际上就是对音频的时间轴的调整，如果存在Offset的情况下
    /// - Parameters:
    ///   - sampleBuffer: Sample buffer input to be appended
    ///   - completionHandler: Handler when a frame appending operation completes or fails
    public func appendAudio(withSampleBuffer sampleBuffer: CMSampleBuffer, completionHandler: @escaping NextLevelSessionAppendSampleBufferCompletionHandler) {
        //存放音频也是通过AVAssetWriter来写入
        self.startSessionIfNecessary(timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        self._audioQueue.async {
            var hasFailed = false

            let buffers = self._skippedAudioBuffers + [sampleBuffer]
            self._skippedAudioBuffers = []
            var failedBuffers: [CMSampleBuffer] = []
            //遍历还未处理的所有的buf41fer
            buffers.forEach { buffer in
                let duration = CMSampleBufferGetDuration(buffer)
                //调整对应的音频Buffer,其实主要就是时间和duration
                if let adjustedBuffer = CMSampleBuffer.createSampleBuffer(fromSampleBuffer: buffer, withTimeOffset: self._timeOffset, duration: duration) {
                    let presentationTimestamp = CMSampleBufferGetPresentationTimeStamp(adjustedBuffer)
                    let lastTimestamp = CMTimeAdd(presentationTimestamp, duration)
                    //加入音频Buffer
                    if let audioInput = self._audioInput,
                       audioInput.isReadyForMoreMediaData,
                       audioInput.append(adjustedBuffer) {
                        //记录上一次的时间戳
                        self._lastAudioTimestamp = lastTimestamp
                        //如果当前没有Video，则需要更新Duration的参数
                        if !self.currentClipHasVideo {
                            self._currentClipDuration = CMTimeSubtract(lastTimestamp, self._startTimestamp)
                        }

                        self._currentClipHasAudio = true
                    } else {
                        //如果失败了，就保存下来，下一次继续尝试
                        failedBuffers.append(buffer)
                        hasFailed = true
                    }
                }
            }

            self._skippedAudioBuffers = failedBuffers
            completionHandler(!hasFailed)
        }
    }

    /// Resets a session to the initial state.
    public func reset() {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            self.endClip(completionHandler: nil)
            self._videoInput = nil
            self._audioInput = nil
            self._pixelBufferAdapter = nil
            self._skippedAudioBuffers = []
            self._videoConfiguration = nil
            self._audioConfiguration = nil
        }
    }

    private func startSessionIfNecessary(timestamp: CMTime) {
        if !self._startTimestamp.isValid {
            self._startTimestamp = timestamp
            self._writer?.startSession(atSourceTime: timestamp)
        }
    }

    // create

    /// Completion handler type for ending a clip
    public typealias NextLevelSessionEndClipCompletionHandler = (_: NextLevelClip?, _: Error?) -> Void

    /// Starts a clip
    public func beginClip() {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            //如果写入文件对象为空
            if self._writer == nil {
                //初始化AssetWriter，AssetWriter的Input
                self.setupWriter()
                self._currentClipDuration = CMTime.zero
                self._currentClipHasAudio = false
                self._currentClipHasVideo = false
            } else {
                print("NextLevel, clip has already been created.")
            }
        }
    }

    /// Finalizes the recording of a clip.
    /// 将此次录制进行一个保存，并且摧毁AVAssetWriter
    /// - Parameter completionHandler: Handler for when a clip is finalized or finalization fails
    public func endClip(completionHandler: NextLevelSessionEndClipCompletionHandler?) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            self._audioQueue.sync {
                if self._currentClipHasStarted {
                    self._currentClipHasStarted = false

                    if let writer = self._writer {
                        //如果当前都没有音频和视频
                        if !self.currentClipHasAudio && !self.currentClipHasVideo {
                            //结束写入文件，退出
                            writer.cancelWriting()
                            // 并且删掉文件，因为没有视频，也没有音频
                            self.removeFile(fileUrl: writer.outputURL)
                            self.destroyWriter()

                            if let completionHandler = completionHandler {
                                DispatchQueue.main.async {
                                    completionHandler(nil, nil)
                                }
                            }
                        } else {
                            //print("ending session \(CMTimeGetSeconds(self._currentClipDuration))")
                            //结束Session
                            writer.endSession(atSourceTime: CMTimeAdd(self._currentClipDuration, self._startTimestamp))
                            //完成写入
                            writer.finishWriting(completionHandler: {
                                self.executeClosureSyncOnSessionQueueIfNecessary {
                                    var clip: NextLevelClip? = nil
                                    let url = writer.outputURL
                                    let error = writer.error

                                    if error == nil {
                                        //从资源文件的URL中，返回Clip的对象
                                        clip = NextLevelClip(url: url, infoDict: nil)
                                        //将这一小片片段都加入到总的统计当中，目前，视频文件夹还是存储到临时目录中
                                        if let clip = clip {
                                            self.add(clip: clip)
                                        }
                                    }
                                    //摧毁Writer
                                    self.destroyWriter()

                                    if let completionHandler = completionHandler {
                                        DispatchQueue.main.async {
                                            completionHandler(clip, error)
                                        }
                                    }
                                }
                            })
                            return
                        }
                    }
                }
                //如果没有开始录制，则直接返回错误
                if let completionHandler = completionHandler {
                    DispatchQueue.main.async {
                        completionHandler(nil, NextLevelError.notReadyToRecord)
                    }
                }
            }
        }
    }
}

// MARK: - clip editing

extension NextLevelSession {

    /// Helper function that provides the location of the last recorded clip.
    /// This is helpful when merging multiple segments isn't desired.
    ///
    /// - Returns: URL path to the last recorded clip.
    public var lastClipUrl: URL? {
        get {
            var lastClipUrl: URL? = nil
            if !self._clips.isEmpty,
               let lastClip = self.clips.last,
               let clipURL = lastClip.url {
                lastClipUrl = clipURL
            }
            return lastClipUrl
        }
    }

    /// Adds a specific clip to a session.
    ///
    /// - Parameter clip: Clip to be added
    public func add(clip: NextLevelClip) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            self._clips.append(clip)
            self._totalDuration = CMTimeAdd(self._totalDuration, clip.duration)
        }
    }

    /// Adds a specific clip to a session at the desired index.
    ///
    /// - Parameters:
    ///   - clip: Clip to be added
    ///   - idx: Index at which to add the clip
    public func add(clip: NextLevelClip, at idx: Int) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            self._clips.insert(clip, at: idx)
            self._totalDuration = CMTimeAdd(self._totalDuration, clip.duration)
        }
    }

    /// Removes a specific clip from a session.
    ///
    /// - Parameter clip: Clip to be removed
    public func remove(clip: NextLevelClip) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            if let idx = self._clips.firstIndex(where: { (clipToEvaluate) -> Bool in
                return clip.uuid == clipToEvaluate.uuid
            }) {
                self._clips.remove(at: idx)
                self._totalDuration = CMTimeSubtract(self._totalDuration, clip.duration)
            }
        }
    }

    /// Removes a clip from a session at the desired index.
    ///
    /// - Parameters:
    ///   - idx: Index of the clip to remove
    ///   - removeFile: True to remove the associated file with the clip
    public func remove(clipAt idx: Int, removeFile: Bool) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            if self._clips.indices.contains(idx) {
                let clip = self._clips.remove(at: idx)
                self._totalDuration = CMTimeSubtract(self._totalDuration, clip.duration)

                if removeFile {
                    clip.removeFile()
                }
            }
        }
    }

    /// Removes and destroys all clips for a session.
    ///
    /// - Parameter removeFiles: When true, associated files are also removed.
    public func removeAllClips(removeFiles: Bool = true) {
        self.executeClosureAsyncOnSessionQueueIfNecessary {
            while !self._clips.isEmpty {
                if let clipToRemove = self._clips.first {
                    if removeFiles {
                        clipToRemove.removeFile()
                    }
                    self._clips.removeFirst()
                }
            }
            self._totalDuration = CMTime.zero
        }
    }

    /// Removes the last recorded clip for a session, "Undo".
    public func removeLastClip() {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            if !self._clips.isEmpty,
               let clipToRemove = self.clips.last {
                self.remove(clip: clipToRemove)
            }
        }
    }

    /// Completion handler type for merging clips, optionals indicate success or failure when nil
    public typealias NextLevelSessionMergeClipsCompletionHandler = (_: URL?, _: Error?) -> Void

    /// Merges all existing recorded clips in the session and exports to a file.
    /// 合并所有的视频
    /// - Parameters:
    ///   - preset: AVAssetExportSession preset name for export
    ///   - completionHandler: Handler for when the merging process completes
    public func mergeClips(usingPreset preset: String, completionHandler: @escaping NextLevelSessionMergeClipsCompletionHandler) {
        self.executeClosureAsyncOnSessionQueueIfNecessary {
            let filename = "\(self.identifier.uuidString)-NL-merged.\(self.fileExtension)"

            let outputURL = NextLevelClip.clipURL(withFilename: filename, directoryPath: self.outputDirectory)
            var asset: AVAsset? = nil

            if !self._clips.isEmpty {

                if self._clips.count == 1 {
                    debugPrint("NextLevel, warning, a merge was requested for a single clip, use lastClipUrl instead")
                }

                asset = self.asset  //这里已经完全合并了所有的tracks

                if let exportAsset = asset, let exportURL = outputURL {
                    self.removeFile(fileUrl: exportURL)
                    //AVAssetExport Session
                    if let exportSession = AVAssetExportSession(asset: exportAsset, presetName: preset) {
                        exportSession.shouldOptimizeForNetworkUse = true
                        exportSession.outputURL = exportURL
                        exportSession.outputFileType = self.fileType
                        //可以导出了，导出结束
                        exportSession.exportAsynchronously {
                            DispatchQueue.main.async {
                                completionHandler(exportURL, exportSession.error)
                            }
                        }
                        return
                    }
                }
            }

            DispatchQueue.main.async {
                completionHandler(nil, NextLevelError.unknown)
            }
        }
    }
}

// MARK: - composition

extension NextLevelSession {

    ///
    /// 应该是将多个片段都赋值到AVMutableComposition这个对象里面
    /// - Parameters:
    ///   - composition:
    ///   - audioMix:
    internal func appendClips(toComposition composition: AVMutableComposition, audioMix: AVMutableAudioMix? = nil) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            var videoTrack: AVMutableCompositionTrack? = nil
            var audioTrack: AVMutableCompositionTrack? = nil

            var currentTime = composition.duration
            //遍历当前的所有Clip片段
            for clip: NextLevelClip in self._clips {
                //获取每一个Asset对象
                if let asset = clip.asset {
                    //获取VideoTracks
                    let videoAssetTracks = asset.tracks(withMediaType: AVMediaType.video)
                    //获取AudioTracks
                    let audioAssetTracks = asset.tracks(withMediaType: AVMediaType.audio)

                    var maxRange = CMTime.invalid

                    var videoTime = currentTime
                    //先对VideoTracks操作
                    for videoAssetTrack in videoAssetTracks {
                        if videoTrack == nil {
                            //合成器的tracks数组
                            let videoTracks = composition.tracks(withMediaType: AVMediaType.video)
                            if videoTracks.count > 0 {
                                videoTrack = videoTracks.first
                            } else {
                                //新建videoTrack
                                videoTrack = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
                                videoTrack?.preferredTransform = videoAssetTrack.preferredTransform
                            }
                        }

                        if let foundTrack = videoTrack {
                            videoTime = self.appendTrack(track: videoAssetTrack, toCompositionTrack: foundTrack, withStartTime: videoTime, range: maxRange)
                            //增加VideoTime
                            maxRange = videoTime
                        }
                    }

                    //如果没有静音
                    if !clip.isMutedOnMerge {
                        var audioTime = currentTime
                        for audioAssetTrack in audioAssetTracks {
                            if audioTrack == nil {
                                let audioTracks = composition.tracks(withMediaType: AVMediaType.audio)

                                if audioTracks.count > 0 {
                                    audioTrack = audioTracks.first
                                } else {
                                    audioTrack = composition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                                }
                            }
                            if let foundTrack = audioTrack {
                                //这里的音轨，也是顺序的输入
                                audioTime = self.appendTrack(track: audioAssetTrack, toCompositionTrack: foundTrack, withStartTime: audioTime, range: maxRange)
                            }
                        }
                    }

                    currentTime = composition.duration
                }
            }
        }
    }

    ///
    /// 增加AVAssetTrack
    /// - Parameters:
    ///   - track:
    ///   - compositionTrack:
    ///   - time:
    ///   - range:
    /// - Returns:
    private func appendTrack(track: AVAssetTrack, toCompositionTrack compositionTrack: AVMutableCompositionTrack, withStartTime time: CMTime, range: CMTime) -> CMTime {
        //这里的track是真的有数据的视频
        var timeRange = track.timeRange
        //当前的startTime
        let startTime = time + timeRange.start

        if range.isValid {
            //如果range是有效的,需要更新range，这个range参数是上一次的视频Range
            let currentRange = startTime + timeRange.duration
            //如果CurrentRange更新后，是在上一个时间轴之后，需要个恒信timeRange，这个timeRange就是以timeRage.start为起点，长度为
            if currentRange > range {
                timeRange = CMTimeRange(start: timeRange.start, duration: (timeRange.duration - (currentRange - range)))
            }
        }
        //如果实际存在的Range Duration 大于0
        if timeRange.duration > CMTime.zero {
            do {
                //加入compititionTrack中
                try compositionTrack.insertTimeRange(timeRange, of: track, at: startTime)
            } catch {
                print("NextLevel, failed to insert composition track")
            }
            //返回当前的时间
            return (startTime + timeRange.duration)
        }

        return startTime
    }

}

// MARK: - file management

extension NextLevelSession {

    ///
    /// 自动生成下一个文件路径
    /// - Returns:
    internal func nextFileURL() -> URL? {
        //生成下一个视频文件的地址
        let filename = "\(self.identifier.uuidString)-NL-clip.\(self._clipFilenameCount).\(self.fileExtension)"
        //这里的outputDirectory是一个临时文件夹
        //拼接URL
        if let url = NextLevelClip.clipURL(withFilename: filename, directoryPath: self.outputDirectory) {
            self.removeFile(fileUrl: url)
            self._clipFilenameCount += 1
            return url
        }
        return nil
    }

    internal func removeFile(fileUrl: URL) {
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            do {
                try FileManager.default.removeItem(atPath: fileUrl.path)
            } catch {
                print("NextLevel, could not remove file at path")
            }
        }
    }
}

// MARK: - queues

extension NextLevelSession {

    internal func executeClosureAsyncOnSessionQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        self._sessionQueue.async(execute: closure)
    }

    internal func executeClosureSyncOnSessionQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: self._sessionQueueKey) != nil {
            closure()
        } else {
            self._sessionQueue.sync(execute: closure)
        }
    }

}
