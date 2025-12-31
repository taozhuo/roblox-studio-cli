import Foundation
import Speech
import AVFoundation

// MARK: - Speech Recognition (Speech-to-Text)

private var speechRecognizer: SFSpeechRecognizer?
private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
private var recognitionTask: SFSpeechRecognitionTask?
private var audioEngine: AVAudioEngine?
private var lastTranscription: String = ""
private var isListening: Bool = false

/// Check if speech recognition permission is granted
@_cdecl("check_speech_permission")
public func checkSpeechPermission() -> Bool {
    return SFSpeechRecognizer.authorizationStatus() == .authorized
}

/// Request speech recognition permission
@_cdecl("request_speech_permission")
public func requestSpeechPermission() {
    SFSpeechRecognizer.requestAuthorization { status in
        print("[DetAI] Speech permission status: \(status.rawValue)")
    }
}

/// Start listening for speech
/// Returns true if started successfully
@_cdecl("start_speech_recognition")
public func startSpeechRecognition() -> Bool {
    guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
        print("[DetAI] Speech recognition not authorized")
        return false
    }

    if isListening {
        print("[DetAI] Already listening")
        return true
    }

    speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    guard let recognizer = speechRecognizer, recognizer.isAvailable else {
        print("[DetAI] Speech recognizer not available")
        return false
    }

    audioEngine = AVAudioEngine()
    guard let engine = audioEngine else {
        return false
    }

    recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
    guard let request = recognitionRequest else {
        return false
    }

    request.shouldReportPartialResults = true

    let inputNode = engine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
        request.append(buffer)
    }

    recognitionTask = recognizer.recognitionTask(with: request) { result, error in
        if let result = result {
            lastTranscription = result.bestTranscription.formattedString
            print("[DetAI] Transcription: \(lastTranscription)")
        }

        if error != nil || (result?.isFinal ?? false) {
            // Recognition ended
        }
    }

    do {
        engine.prepare()
        try engine.start()
        isListening = true
        print("[DetAI] Started speech recognition")
        return true
    } catch {
        print("[DetAI] Failed to start audio engine: \(error)")
        return false
    }
}

/// Stop listening for speech
@_cdecl("stop_speech_recognition")
public func stopSpeechRecognition() {
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()

    audioEngine = nil
    recognitionRequest = nil
    recognitionTask = nil
    isListening = false

    print("[DetAI] Stopped speech recognition")
}

/// Get the last transcription result
/// Returns pointer to SRString or null
@_cdecl("get_transcription")
public func getTranscription() -> UnsafeMutableRawPointer? {
    if lastTranscription.isEmpty {
        return nil
    }
    let srString = SRString(lastTranscription)
    return Unmanaged.passRetained(srString).toOpaque()
}

/// Check if currently listening
@_cdecl("is_listening")
public func isCurrentlyListening() -> Bool {
    return isListening
}

// MARK: - Text-to-Speech

private var speechSynthesizer: AVSpeechSynthesizer?
private var isSpeaking: Bool = false

/// Speak text using system TTS
@_cdecl("speak_text")
public func speakText(_ textPtr: UnsafePointer<CChar>?) -> Bool {
    guard let textPtr = textPtr else {
        return false
    }

    let text = String(cString: textPtr)

    if speechSynthesizer == nil {
        speechSynthesizer = AVSpeechSynthesizer()
    }

    guard let synth = speechSynthesizer else {
        return false
    }

    // Stop any current speech
    if synth.isSpeaking {
        synth.stopSpeaking(at: .immediate)
    }

    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.pitchMultiplier = 1.0
    utterance.volume = 1.0

    synth.speak(utterance)
    isSpeaking = true
    print("[DetAI] Speaking: \(text.prefix(50))...")

    return true
}

/// Stop speaking
@_cdecl("stop_speaking")
public func stopSpeaking() {
    speechSynthesizer?.stopSpeaking(at: .immediate)
    isSpeaking = false
}

/// Check if currently speaking
@_cdecl("is_speaking")
public func isCurrentlySpeaking() -> Bool {
    return speechSynthesizer?.isSpeaking ?? false
}

// MARK: - SRString wrapper for FFI

@objc public class SRString: NSObject {
    var string: String

    init(_ string: String) {
        self.string = string
    }
}

@_cdecl("sr_string_value")
public func srStringValue(_ ptr: UnsafeMutableRawPointer) -> UnsafePointer<CChar>? {
    let srString = Unmanaged<SRString>.fromOpaque(ptr).takeUnretainedValue()
    return (srString.string as NSString).utf8String
}

@_cdecl("sr_string_free")
public func srStringFree(_ ptr: UnsafeMutableRawPointer) {
    let _ = Unmanaged<SRString>.fromOpaque(ptr).takeRetainedValue()
}
