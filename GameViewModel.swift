import Foundation
@preconcurrency import AVFoundation
import Vision
import SwiftUI

@MainActor
class GameViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // ===== Camera =====
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "camera.capture.queue")
    nonisolated(unsafe) private let poseRequest = VNDetectHumanBodyPoseRequest()
    nonisolated(unsafe) private let estimator = PoseEstimator()

    // ===== Game State =====
    @Published var totalScore: Int = 0
    @Published var clearCount: Int = 0
    @Published var poseTimeRemaining: Int = 10
    @Published var gameEnded: Bool = false
    @Published var currentPose: GamePose = .armsUp
    @Published var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var isNextPoseButtonEnabled: Bool = false
    @Published var isBossPhase: Bool = false
    @Published var currentBossPose: GamePose? = nil
    @Published var cameraErrorMessage: String?
    private let bossScoreThreshold: Int = 60

    nonisolated(unsafe) private var isCheckingPose = false
    nonisolated(unsafe) private var currentPoseForCapture: GamePose = .armsUp
    private var isSessionConfigured = false

    private var poseTimer: Timer?

    // ===== Init =====
    override init() {
        super.init()
    }

    // ===== Camera Setup =====
    private func setupCameraIfNeeded() -> Bool {
        if isSessionConfigured {
            return true
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera,
                                       for: .video,
                                       position: .back)
            ?? AVCaptureDevice.default(for: .video) else {
            cameraErrorMessage = "No camera device is available on this runtime."
            return false
        }

        guard
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            cameraErrorMessage = "Failed to configure camera input."
            return false
        }

        captureSession.addInput(input)

        guard captureSession.canAddOutput(videoOutput) else {
            cameraErrorMessage = "Failed to configure camera output."
            return false
        }
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            // For front camera, mirror so it feels natural like a selfie view
            if connection.isVideoMirroringSupported && device.position == .front {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            // Stabilization (optional)
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .standard
            }
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        // Set a pixel format commonly used by Vision
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        isSessionConfigured = true
        cameraErrorMessage = nil
        return true
    }

    // ===== Game Control =====
    func startGame() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let isAuthorized = await self.ensureCameraAuthorization()
            guard isAuthorized else {
                self.cameraErrorMessage = "Camera access is denied. Allow camera access in Settings."
                return
            }

            guard self.setupCameraIfNeeded() else { return }

            self.isBossPhase = false
            self.currentBossPose = nil
            if !self.captureSession.isRunning {
                let session = self.captureSession
                self.captureQueue.async {
                    session.startRunning()
                }
            }
            self.startTimers()
            self.selectRandomPose()
            self.isNextPoseButtonEnabled = false
            self.cameraErrorMessage = nil
        }
    }

    func stopGame() {
        let session = captureSession
        captureQueue.async {
            session.stopRunning()
        }
        poseTimer?.invalidate()
        gameEnded = true
    }

    func resetGame() {
        totalScore = 0
        clearCount = 0
        poseTimeRemaining = 10
        gameEnded = false
        isBossPhase = false
        currentBossPose = nil
        isNextPoseButtonEnabled = false
        startGame()
    }

    // ===== Timer =====
    private func startTimers() {
        poseTimer?.invalidate()
        poseTimeRemaining = 10

        poseTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.poseTimeRemaining -= 1
                if self.poseTimeRemaining <= 0 {
                    self.selectRandomPose()
                    self.poseTimeRemaining = 10
                }
            }
        }
    }

    // ===== Pose =====
    private func selectRandomPose() {
        if let bossPose = currentBossPose {
            currentPose = bossPose
        } else {
            currentPose = GamePose.allCases.randomElement() ?? .armsUp
        }
        currentPoseForCapture = currentPose
        isCheckingPose = false
    }

    // ===== Boss =====
    private func enterBossPhase(with pose: GamePose? = nil) {
        isBossPhase = true
        // Choose a specific boss pose if provided, otherwise reuse current or pick randomly
        if let pose {
            currentBossPose = pose
        } else {
            currentBossPose = currentPose
        }
        // When entering boss phase, refresh the timer to give the player a full window
        poseTimeRemaining = 10
        selectRandomPose()
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

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if isCheckingPose { return }
        isCheckingPose = true

        let pose = currentPoseForCapture

        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
            .leftWrist, .rightWrist, .leftHip, .rightHip, .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle
        ]
        
        let imageOrientation: CGImagePropertyOrientation = connection.isVideoMirrored ? .upMirrored : .up

        estimator.process(sampleBuffer: sampleBuffer, orientation: imageOrientation) { [weak self] observation in
            guard let self = self, let observation = observation else {
                self?.isCheckingPose = false
                return
            }

            // ✅ nonisolatedコンテキストでobservationからデータを抽出してしまう
            let score = pose.calculateScore(observation: observation)

            var extractedJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
            for joint in jointNames {
                guard let p = try? observation.recognizedPoint(joint), p.confidence > 0.3 else { continue }
                extractedJoints[joint] = CGPoint(x: p.location.x, y: 1 - p.location.y)
            }

            // ✅ Taskにはobservationではなく抽出済みデータだけを渡す
            Task { @MainActor in
                self.joints = extractedJoints

                if score > 30 {
                    self.totalScore += score
                    self.clearCount += 1
                    if score > self.bossScoreThreshold && !self.isBossPhase {
                        // Enter boss phase when a single pose score exceeds threshold
                        self.enterBossPhase(with: self.currentPose)
                        self.isNextPoseButtonEnabled = false
                    } else if self.isBossPhase {
                        // In boss phase: upon a successful match, exit boss phase and continue
                        self.isBossPhase = false
                        self.currentBossPose = nil
                        self.selectRandomPose()
                        self.isNextPoseButtonEnabled = false
                        self.poseTimeRemaining = 10
                    } else {
                        self.selectRandomPose()
                        self.isNextPoseButtonEnabled = false
                        self.poseTimeRemaining = 10
                    }
                }

                self.isCheckingPose = false
            }
        }
    }
}
