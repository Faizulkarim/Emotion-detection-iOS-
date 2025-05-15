import SwiftUI
import ARKit
import RealityKit
import Speech
import AVFoundation

struct EmotionDetectionView: View {
    @StateObject private var viewModel = ARViewModel()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isRecording = false
    
    var body: some View {
        ZStack {
            ARViewContainer(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                // Face Emotion Display
                Text("Face Emotion: \(viewModel.currentEmotion)")
                    .font(.title)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.bottom, 10)
                
                // Voice Emotion Display
                Text("Voice Emotion: \(speechRecognizer.detectedEmotion)")
                    .font(.title)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.bottom, 20)
                
                // Record Button
                Button {
                    if isRecording {
                        endRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 70))
                        .foregroundColor(isRecording ? .red : .blue)
                        .padding()
                }
                .padding(.bottom, 30)
            }
        }
        .alert("Error", isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage)
        }
    }
    
    private func startRecording() {
        speechRecognizer.resetTranscript()
        speechRecognizer.startTranscribing()
        isRecording = true
    }
    
    private func endRecording() {
        speechRecognizer.stopTranscribing()
        isRecording = false
    }
}

@MainActor
class ARViewModel: ObservableObject {
    @Published var currentEmotion: String = "No face detected"
    @Published var showAlert = false
    @Published var alertMessage = ""
    
    func updateEmotion(from faceAnchor: ARFaceAnchor) {
        let blendShapes = faceAnchor.blendShapes
        
        // Get all relevant blend shape values
        let smileValue = blendShapes[.mouthSmileLeft]?.floatValue ?? 0
        let smileRightValue = blendShapes[.mouthSmileRight]?.floatValue ?? 0
        let frownValue = blendShapes[.mouthFrownLeft]?.floatValue ?? 0
        let frownRightValue = blendShapes[.mouthFrownRight]?.floatValue ?? 0
        let jawOpenValue = blendShapes[.jawOpen]?.floatValue ?? 0
        let browInnerUpValue = blendShapes[.browInnerUp]?.floatValue ?? 0
        let browOuterUpLeftValue = blendShapes[.browOuterUpLeft]?.floatValue ?? 0
        let browOuterUpRightValue = blendShapes[.browOuterUpRight]?.floatValue ?? 0
        let eyeBlinkLeftValue = blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
        let eyeBlinkRightValue = blendShapes[.eyeBlinkRight]?.floatValue ?? 0
        let eyeSquintLeftValue = blendShapes[.eyeSquintLeft]?.floatValue ?? 0
        let eyeSquintRightValue = blendShapes[.eyeSquintRight]?.floatValue ?? 0
        
        // Calculate average values for symmetrical features
        let averageSmile = (smileValue + smileRightValue) / 2
        let averageFrown = (frownValue + frownRightValue) / 2
        let averageBrowOuterUp = (browOuterUpLeftValue + browOuterUpRightValue) / 2
        let averageEyeBlink = (eyeBlinkLeftValue + eyeBlinkRightValue) / 2
        let averageEyeSquint = (eyeSquintLeftValue + eyeSquintRightValue) / 2
        
        // Determine the emotion based on blend shape values with adjusted thresholds
        if averageSmile > 0.4 && averageEyeSquint < 0.3 {
            currentEmotion = "Happy"
        } else if averageFrown > 0.4 && browInnerUpValue > 0.3 {
            currentEmotion = "Angry"
        } else if averageFrown > 0.4 && browInnerUpValue < 0.2 {
            currentEmotion = "Sad"
        } else if jawOpenValue > 0.4 && averageEyeBlink < 0.3 {
            currentEmotion = "Surprised"
        } else if averageEyeSquint > 0.4 && averageSmile < 0.2 {
            currentEmotion = "Disgusted"
        } else if averageBrowOuterUp > 0.4 && averageSmile < 0.2 {
            currentEmotion = "Fearful"
        } else if averageSmile > 0.2 || averageFrown > 0.2 || jawOpenValue > 0.2 || browInnerUpValue > 0.2 {
            // If any significant expression is detected but doesn't match above patterns
            currentEmotion = "Expressive"
        } else {
            currentEmotion = "Neutral"
        }
    }
}

actor SpeechRecognizer: ObservableObject {
    @MainActor @Published var transcript: String = ""
    @MainActor @Published var detectedEmotion: String = "No voice detected"
    
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?
    private var isTapInstalled = false
    
    // Audio analysis parameters - now actor-isolated
    private var pitchValues: [Float] = []
    private var intensityValues: [Float] = []
    
    init() {
        recognizer = SFSpeechRecognizer()
        
        Task {
            do {
                guard await SFSpeechRecognizer.hasAuthorizationToRecognize() else {
                    throw RecognizerError.notAuthorizedToRecognize
                }
                guard await AVAudioSession.sharedInstance().hasPermissionToRecord() else {
                    throw RecognizerError.notPermittedToRecord
                }
                
                // Configure audio session
                try await configureAudioSession()
            } catch {
                transcribe(error)
            }
        }
    }
    
    private func configureAudioSession() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        try await audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try await audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Wait a short time to ensure audio session is fully configured
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    @MainActor func startTranscribing() {
        Task {
            await transcribe()
        }
    }
    
    @MainActor func resetTranscript() {
        transcript = ""
        detectedEmotion = "No voice detected"
        Task {
            await resetAudioAnalysis()
        }
    }
    
    private func resetAudioAnalysis() {
        pitchValues.removeAll()
        intensityValues.removeAll()
    }
    
    @MainActor func stopTranscribing() {
        Task {
            await reset()
            await analyzeEmotion()
        }
    }
    
    private func analyzeEmotion() {
        guard !pitchValues.isEmpty && !intensityValues.isEmpty else { return }
        
        // Calculate statistics
        let avgPitch = pitchValues.reduce(0, +) / Float(pitchValues.count)
        let avgIntensity = intensityValues.reduce(0, +) / Float(intensityValues.count)
        let pitchVariation = calculateVariation(pitchValues)
        let intensityVariation = calculateVariation(intensityValues)
        
        // Calculate pitch range
        let maxPitch = pitchValues.max() ?? 0
        let minPitch = pitchValues.min() ?? 0
        let pitchRange = maxPitch - minPitch
        
        // Calculate intensity range
        let maxIntensity = intensityValues.max() ?? 0
        let minIntensity = intensityValues.min() ?? 0
        let intensityRange = maxIntensity - minIntensity
        
        // Analyze emotion based on multiple factors
        let emotion: String
        
        // Excited: High intensity, high pitch variation, wide pitch range
        if avgIntensity > 0.6 && pitchVariation > 0.25 && pitchRange > 0.3 {
            emotion = "Excited"
        }
        // Happy: Moderate to high pitch, good variation, moderate intensity
        else if avgPitch > 0.5 && pitchVariation > 0.2 && avgIntensity > 0.4 {
            emotion = "Happy"
        }
        // Angry: High intensity, low pitch variation, consistent high pitch
        else if avgIntensity > 0.7 && pitchVariation < 0.15 && avgPitch > 0.6 {
            emotion = "Angry"
        }
        // Sad: Low intensity, low pitch variation, low pitch
        else if avgIntensity < 0.4 && pitchVariation < 0.1 && avgPitch < 0.4 {
            emotion = "Sad"
        }
        // Calm: Low intensity, low variation, moderate pitch
        else if avgIntensity < 0.5 && pitchVariation < 0.15 && avgPitch > 0.3 && avgPitch < 0.6 {
            emotion = "Calm"
        }
        // Neutral: Everything else
        else {
            emotion = "Neutral"
        }
        
        Task { @MainActor in
            detectedEmotion = emotion
        }
    }
    
    private func calculateVariation(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Float(values.count)
        return sqrt(variance)
    }
    
    private func analyzeAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = UInt(buffer.frameLength)
        
        // Calculate pitch using zero crossing rate
        var zeroCrossings = 0
        for i in 1..<Int(frameCount) {
            if channelData[i] * channelData[i-1] < 0 {
                zeroCrossings += 1
            }
        }
        let pitch = Float(zeroCrossings) / Float(frameCount)
        
        // Calculate intensity wwusing RMS with normalization
        var sum: Float = 0
        for i in 0..<Int(frameCount) {
            sum += channelData[i] * channelData[i]
        }
        let intensity = sqrt(sum / Float(frameCount))
        
        // Normalize values to 0-1 range
        let normalizedPitch = min(max(pitch / 0.5, 0), 1)  // Assuming max pitch is around 0.5
        let normalizedIntensity = min(max(intensity * 2, 0), 1)  // Scale intensity appropriately
        
        // Update actor-isolated properties
        pitchValues.append(normalizedPitch)
        intensityValues.append(normalizedIntensity)
    }
    
    private func transcribe() {
        guard let recognizer, recognizer.isAvailable else {
            self.transcribe(RecognizerError.recognizerIsUnavailable)
            return
        }
        
        do {
            // Create new audio engine instance
            let audioEngine = AVAudioEngine()
            self.audioEngine = audioEngine
            
            // Ensure audio session is configured
            try AVAudioSession.sharedInstance().setActive(true)
            
            // Create and configure request
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            
            // Remove any existing tap
            if isTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                isTapInstalled = false
            }
            
            // Get the native format of the input node
            let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
            
            // Install tap with native format
            audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
                self?.analyzeAudioBuffer(buffer)
                request.append(buffer)
            }
            isTapInstalled = true
            
            // Start the engine
            try audioEngine.start()
            
            // Start recognition task
            self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                self?.recognitionHandler(audioEngine: audioEngine, result: result, error: error)
            }
        } catch {
            self.reset()
            self.transcribe(error)
        }
    }
    
    private func reset() {
        task?.cancel()
        if let audioEngine = audioEngine {
            if isTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                isTapInstalled = false
            }
            audioEngine.stop()
        }
        audioEngine = nil
        request = nil
        task = nil
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    nonisolated private func recognitionHandler(audioEngine: AVAudioEngine, result: SFSpeechRecognitionResult?, error: Error?) {
        let receivedFinalResult = result?.isFinal ?? false
        let receivedError = error != nil
        
        if receivedFinalResult || receivedError {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        if let result {
            transcribe(result.bestTranscription.formattedString)
        }
    }
    
    nonisolated private func transcribe(_ message: String) {
        Task { @MainActor in
            transcript = message
        }
    }
    
    nonisolated private func transcribe(_ error: Error) {
        var errorMessage = ""
        if let error = error as? RecognizerError {
            errorMessage += error.message
        } else {
            errorMessage += error.localizedDescription
        }
        Task { @MainActor [errorMessage] in
            transcript = "<< \(errorMessage) >>"
        }
    }
}

enum RecognizerError: Error {
    case nilRecognizer
    case notAuthorizedToRecognize
    case notPermittedToRecord
    case recognizerIsUnavailable
    
    var message: String {
        switch self {
        case .nilRecognizer: return "Can't initialize speech recognizer"
        case .notAuthorizedToRecognize: return "Not authorized to recognize speech"
        case .notPermittedToRecord: return "Not permitted to record audio"
        case .recognizerIsUnavailable: return "Recognizer is unavailable"
        }
    }
}

extension SFSpeechRecognizer {
    static func hasAuthorizationToRecognize() async -> Bool {
        await withCheckedContinuation { continuation in
            requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

extension AVAudioSession {
    func hasPermissionToRecord() async -> Bool {
        await withCheckedContinuation { continuation in
            requestRecordPermission { authorized in
                continuation.resume(returning: authorized)
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let viewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure AR session
        guard ARFaceTrackingConfiguration.isSupported else {
            viewModel.showAlert = true
            viewModel.alertMessage = "Face tracking is not supported on this device"
            return arView
        }
        
        let configuration = ARFaceTrackingConfiguration()
        arView.session.run(configuration)
        arView.session.delegate = context.coordinator
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        let viewModel: ARViewModel
        
        init(viewModel: ARViewModel) {
            self.viewModel = viewModel
        }
        
        nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard let faceAnchor = anchors.first as? ARFaceAnchor else { return }
            Task { @MainActor in
                viewModel.updateEmotion(from: faceAnchor)
            }
        }
    }
} 
