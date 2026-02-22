import Foundation
import AVFoundation
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
        setupCamera()
        startTimer()
    }

    // MARK: - カメラ設定
    func setupCamera() {
        session.beginConfiguration()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()

        // delegate は extension 側で受ける
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "cameraQueue"))

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.commitConfiguration()
        session.startRunning()
    }

    // MARK: - タイマー
    func startTimer() {
        timeRemaining = 10

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.timeRemaining -= 1

            if self.timeRemaining <= 0 {
                self.failPose()
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
