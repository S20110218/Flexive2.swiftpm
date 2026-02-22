import SwiftUI

struct GameView: View {

    @StateObject private var viewModel = GameViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {

            CameraPreviewView(session: viewModel.captureSession)
                .ignoresSafeArea()

            VStack(spacing: 16) {

                Spacer()

                Text("Pose Game")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text("Score: \(viewModel.totalScore)")
                    .foregroundColor(.white)

                Text("Clear: \(viewModel.clearCount)")
                    .foregroundColor(.white)

                Text("Time: \(viewModel.poseTimeRemaining)")
                    .foregroundColor(.white)

                Spacer()

                HStack(spacing: 20) {

                    Button("Start") { viewModel.startGame() }
                    Button("Stop") { viewModel.stopGame() }
                    Button("Reset") { viewModel.resetGame() }
                    Button("Back") { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 40)
            }
        }
    }
}
