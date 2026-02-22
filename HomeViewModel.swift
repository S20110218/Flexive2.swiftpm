import Foundation
import AVFoundation
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

    // MARK: - Camera Properties
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let poseEstimator = PoseEstimator()
    nonisolated private let poseRepository = PoseTemplateRepository.shared
    nonisolated(unsafe) private var currentPoseTemplateForCapture: PoseTemplate

    private let poseRequest = VNDetectHumanBodyPoseRequest()

    override init() {
        let initial = poseRepository.random()
        self.currentPoseTemplate = initial
        self.currentPoseTemplateForCapture = initial
        super.init()
        setupCamera()
    }
    
    // MARK: - Public Methods
    
    func startSession() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isCameraActive = true
            }
        }
    }
    
    func stopSession() {
        guard captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                self?.isCameraActive = false
            }
        }
    }
    
    func loadNextPose() {
        let next = poseRepository.random()
        self.currentPoseTemplate = next
        self.currentPoseTemplateForCapture = next  // nonisolated用にコピー
        self.score = 0.0
    }
    
    // MARK: - Camera Setup
    
    private func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            captureSession.commitConfiguration()
            return
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        let videoQueue = DispatchQueue(label: "HomeVideoQueue", qos: .userInteractive)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        captureSession.commitConfiguration()
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        poseEstimator.process(sampleBuffer: sampleBuffer) { [weak self] observation in
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

           
            Task { @MainActor in
                self.userJoints = extractedJoints
                self.score = newScore
            }
        }
    }
}
