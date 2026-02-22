import Foundation
@preconcurrency import AVFoundation
import Vision
import Combine
import SwiftUI

@MainActor
class HomeViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK: - Published Properties
    @Published var userJoints: [VNHumanBodyPoseObservation.JointName : CGPoint] = [:]
    @Published var currentPoseTemplate: PoseTemplate
    @Published var score: Double = 0.0
    @Published var isCameraActive = false
    @Published var cameraErrorMessage: String?

    // MARK: - Camera Properties
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isSessionConfigured = false
    private let defaultAutoAdvanceThreshold: Double = 0.50
    private let jumpingJackAutoAdvanceThreshold: Double = 0.40
    private let autoAdvanceDelay: TimeInterval = 0.8
    private var autoAdvanceCooldownUntil: Date = .distantPast
    private var pendingAutoAdvanceTask: Task<Void, Never>?
    private var pendingAutoAdvancePoseName: String?
    nonisolated(unsafe) private let poseEstimator = PoseEstimator()
    nonisolated private let poseRepository = PoseTemplateRepository.shared
    nonisolated(unsafe) private var currentPoseTemplateForCapture: PoseTemplate

    private let poseRequest = VNDetectHumanBodyPoseRequest()

    override init() {
        let initial = poseRepository.random()
        self.currentPoseTemplate = initial
        self.currentPoseTemplateForCapture = initial
        super.init()
    }
    
    // MARK: - Public Methods
    
    func startSession() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let isAuthorized = await self.ensureCameraAuthorization()
            guard isAuthorized else {
                self.cameraErrorMessage = "Camera access is denied. Allow camera access in Settings."
                self.isCameraActive = false
                return
            }

            guard self.setupCameraIfNeeded() else {
                self.isCameraActive = false
                return
            }

            guard !self.captureSession.isRunning else {
                self.cameraErrorMessage = nil
                self.isCameraActive = true
                return
            }

            let session = self.captureSession
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                session.startRunning()
                Task { @MainActor in
                    self?.isCameraActive = session.isRunning
                    if session.isRunning {
                        self?.cameraErrorMessage = nil
                    } else if self?.cameraErrorMessage == nil {
                        self?.cameraErrorMessage = "Failed to start camera session."
                    }
                }
            }
        }
    }
    
    func stopSession() {
        pendingAutoAdvanceTask?.cancel()
        pendingAutoAdvanceTask = nil
        pendingAutoAdvancePoseName = nil

        guard captureSession.isRunning else {
            isCameraActive = false
            return
        }
        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.stopRunning()
            Task { @MainActor in
                self?.isCameraActive = false
            }
        }
    }
    
    func loadNextPose() {
        pendingAutoAdvanceTask?.cancel()
        pendingAutoAdvanceTask = nil
        pendingAutoAdvancePoseName = nil

        let next = poseRepository.random()
        self.currentPoseTemplate = next
        self.currentPoseTemplateForCapture = next  // nonisolated用にコピー
        self.score = 0.0
        // Prevent stale frames from immediately skipping another pose.
        self.autoAdvanceCooldownUntil = Date().addingTimeInterval(0.35)
    }
    
    // MARK: - Camera Setup
    
    private func setupCameraIfNeeded() -> Bool {
        if isSessionConfigured {
            return true
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .high
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video) else {
            cameraErrorMessage = "No camera device is available on this runtime."
            return false
        }

        guard let input = try? AVCaptureDeviceInput(device: camera) else {
            cameraErrorMessage = "Failed to create camera input."
            return false
        }
        
        guard captureSession.canAddInput(input) else {
            cameraErrorMessage = "Cannot add camera input to session."
            return false
        }
        captureSession.addInput(input)
        
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        let videoQueue = DispatchQueue(label: "HomeVideoQueue", qos: .userInteractive)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        guard captureSession.canAddOutput(videoOutput) else {
            cameraErrorMessage = "Cannot add camera output to session."
            return false
        }
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported && camera.position == .front {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }

        isSessionConfigured = true
        cameraErrorMessage = nil
        return true
    }

    private func ensureCameraAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func autoAdvanceThreshold(for poseName: String) -> Double {
        if poseName.caseInsensitiveCompare("Jumping Jack") == .orderedSame {
            return jumpingJackAutoAdvanceThreshold
        }
        return defaultAutoAdvanceThreshold
    }

    private func scheduleAutoAdvance(for poseName: String) {
        guard pendingAutoAdvanceTask == nil else { return }

        pendingAutoAdvancePoseName = poseName
        autoAdvanceCooldownUntil = Date().addingTimeInterval(autoAdvanceDelay)

        let delayNanos = UInt64(autoAdvanceDelay * 1_000_000_000)
        pendingAutoAdvanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            self?.performDelayedAutoAdvance(for: poseName)
        }
    }

    private func performDelayedAutoAdvance(for poseName: String) {
        defer {
            pendingAutoAdvanceTask = nil
            pendingAutoAdvancePoseName = nil
        }

        guard pendingAutoAdvancePoseName == poseName else { return }
        loadNextPose()
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let imageOrientation: CGImagePropertyOrientation = connection.isVideoMirrored ? .upMirrored : .up

        poseEstimator.process(sampleBuffer: sampleBuffer, orientation: imageOrientation) { [weak self] observation in
            guard let self = self, let observation = observation else { return }

            
            let jointNames: [VNHumanBodyPoseObservation.JointName] = [
                .nose, .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
                .leftWrist, .rightWrist, .leftHip, .rightHip, .leftKnee, .rightKnee,
                .leftAnkle, .rightAnkle
            ]
            var extractedJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
            for joint in jointNames {
                guard let p = try? observation.recognizedPoint(joint), p.confidence > 0.3 else { continue }
                extractedJoints[joint] = CGPoint(x: p.location.x, y: 1 - p.location.y)
            }

            let newScore = self.poseEstimator.score(current: extractedJoints, target: self.currentPoseTemplateForCapture.joints)
            let poseName = self.currentPoseTemplateForCapture.name

           
            Task { @MainActor in
                let now = Date()
                let threshold = self.autoAdvanceThreshold(for: poseName)
                let shouldAutoAdvance = newScore >= threshold && now >= self.autoAdvanceCooldownUntil

                self.userJoints = extractedJoints
                self.score = newScore

                if shouldAutoAdvance {
                    self.scheduleAutoAdvance(for: poseName)
                }
            }
        }
    }
}
