import AppKit
import AVFoundation
import Combine

public enum WorkoutFeedbackAudioMode: String, CaseIterable {
    case off
    case tone
    case spoken
}

@MainActor
final class WorkoutFeedbackSpeaker: ObservableObject {
    static let audioModeStorageKey = "workoutFeedbackAudioMode"

    private let synthesizer = AVSpeechSynthesizer()

    func play(_ event: WorkoutFeedbackEvent, modeRawValue: String) {
        let mode = WorkoutFeedbackAudioMode(rawValue: modeRawValue) ?? .spoken
        switch mode {
        case .off:
            synthesizer.stopSpeaking(at: .immediate)
        case .tone:
            synthesizer.stopSpeaking(at: .immediate)
            NSSound.beep()
        case .spoken:
            synthesizer.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: event.spokenText)
            utterance.rate = 0.52
            utterance.volume = 0.85
            synthesizer.speak(utterance)
        }
    }
}
