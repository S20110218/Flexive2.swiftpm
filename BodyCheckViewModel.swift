import Foundation
@preconcurrency import AVFoundation
import Vision

enum PoseType: String {
    case pose1 = "ポーズ1"
    case pose2 = "ポーズ2"
    case pose3 = "ポーズ3"
}

@MainActor
class BodyCheckViewModel: NSObject, ObservableObject {

    // ===== カメラ =====
    let session = AVCaptureSession()
    @Published var cameraErrorMessage: String?
    private var isSessionConfigured = false
    private let cameraQueue = DispatchQueue(label: "BodyCheck.camera.queue")

    // ===== ポーズ =====
    @Published var currentPoseIndex: Int = 0
    let poses: [PoseType] = [.pose1, .pose2, .pose3]

    var currentPose: PoseType {
        poses[currentPoseIndex]
    }

    // ===== スコア =====
    @Published var score: Int = 0
    @Published var combo: Int = 0

    // ===== タイマー =====
    @Published var timeRemaining: Int = 10
    var timer: Timer?

    // ===== 演出 =====
    @Published var showClearEffect: Bool = false
    @Published var showGameClear: Bool = false

    // MARK: - 初期化
    override init() {
        super.init()
        Task { @MainActor [weak self] in
            await self?.prepareCamera()
        }
        startTimer()
    }

    private func prepareCamera() async {
        let isAuthorized = await ensureCameraAuthorization()
        guard isAuthorized else {
            cameraErrorMessage = "Camera access is denied. Allow camera access in Settings."
            return
        }

        guard setupCameraIfNeeded() else { return }

        if !session.isRunning {
            let captureSession = session
            cameraQueue.async {
                captureSession.startRunning()
            }
        }
    }

    // MARK: - カメラ設定
    private func setupCameraIfNeeded() -> Bool {
        if isSessionConfigured {
            return true
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video) else {
            cameraErrorMessage = "No camera device is available on this runtime."
            return false
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            cameraErrorMessage = "Failed to create camera input."
            return false
        }

        guard session.canAddInput(input) else {
            cameraErrorMessage = "Cannot add camera input to session."
            return false
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()

        // delegate は extension 側で受ける
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(output) else {
            cameraErrorMessage = "Cannot add camera output to session."
            return false
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported && device.position == .front {
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

    // MARK: - タイマー
    func startTimer() {
        timeRemaining = 10

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.timeRemaining -= 1
                if self.timeRemaining <= 0 {
                    self.failPose()
                }
            }
        }
    }

    func failPose() {
        combo = 0
        score = 0
        startTimer()
    }

    // MARK: - スコア更新
    func updateScore(newScore: Int) {
        score = newScore

        if score >= 60 {
            combo += 1
            showClearEffect = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showClearEffect = false
                self.goToNextPose()
            }
        }
    }

    // MARK: - 次ポーズ
    func goToNextPose() {
        timer?.invalidate()

        if currentPoseIndex < poses.count - 1 {
            currentPoseIndex += 1
            score = 0
            startTimer()
        } else {
            showGameClear = true
        }
    }

    // MARK: - リスタート
    func restartGame() {
        currentPoseIndex = 0
        score = 0
        combo = 0
        showGameClear = false
        startTimer()
    }
}

//
// 🔥 Swift6対応の安全な delegate 実装
//
extension BodyCheckViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {

        let randomScore = Int.random(in: 0...100)

        Task { @MainActor in
            self.updateScore(newScore: randomScore)
        }
    }
}
