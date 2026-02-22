import SwiftUI
import AVFoundation

class SoundPlayer: NSObject {
    let soundData1 = NSDataAsset(name: "OK")!.data
    var player : AVAudioPlayer!
    
    // ボタン音
    func playOkSound() {
        do {
            player = try AVAudioPlayer(data: soundData1)
            player.play()
        } catch {
            print("error")
        }
    }
}
