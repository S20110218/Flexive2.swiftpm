import SwiftUI

struct BodyCheckView: View {

    @StateObject var viewModel = BodyCheckViewModel()

    var body: some View {
        ZStack {

            // カメラ表示
            CameraPreviewView(session: viewModel.session)
                .ignoresSafeArea()

            VStack {
                Spacer()

                VStack(spacing: 10) {

                    Text(viewModel.currentPose.rawValue)
                        .font(.title)
                        .bold()
                        .foregroundColor(.white)

                    Text("Score: \(viewModel.score)")
                        .font(.largeTitle)
                        .foregroundColor(.white)

                    Text("Time: \(viewModel.timeRemaining)")
                        .foregroundColor(.red)

                    Text("Combo: \(viewModel.combo)")
                        .foregroundColor(.yellow)

                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(15)

                Spacer()
            }

            // クリア表示
            if viewModel.showClearEffect {
                Text("CLEAR!")
                    .font(.system(size: 60))
                    .bold()
                    .foregroundColor(.green)
            }

            // ゲームクリア表示
            if viewModel.showGameClear {
                VStack(spacing: 20) {
                    Text("🎉 GAME CLEAR 🎉")
                        .font(.largeTitle)
                        .bold()

                    Button("もう一回") {
                        viewModel.restartGame()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding()
                .background(Color.white)
                .cornerRadius(20)
            }

            if let cameraErrorMessage = viewModel.cameraErrorMessage {
                VStack(spacing: 8) {
                    Text("Camera Unavailable")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(cameraErrorMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(16)
                .background(Color.black.opacity(0.75))
                .cornerRadius(12)
                .padding()
            }
        }
    }
}
