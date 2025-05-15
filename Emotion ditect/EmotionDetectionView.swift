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
                
                // Face Emotion Display with Confidence
                Text("Face Emotion: \(viewModel.currentEmotion) (\(Int(viewModel.emotionConfidence * 100))%)")
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
    @Published var emotionConfidence: Double = 0.0
    @Published var showAlert = false
    @Published var alertMessage = ""
    
    // Temporal smoothing
    private let maxFrameHistory = 15
    private var emotionHistory: [(emotion: String, confidence: Double)] = []
    
    private struct EmotionScore {
        let emotion: String
        let score: Double
    }
    
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
        let noseSneerLeftValue = blendShapes[.noseSneerLeft]?.floatValue ?? 0
        let noseSneerRightValue = blendShapes[.noseSneerRight]?.floatValue ?? 0
        let cheekPuffValue = blendShapes[.cheekPuff]?.floatValue ?? 0
        let tongueOutValue = blendShapes[.tongueOut]?.floatValue ?? 0
        let mouthPuckerValue = blendShapes[.mouthPucker]?.floatValue ?? 0
        let mouthFunnelValue = blendShapes[.mouthFunnel]?.floatValue ?? 0
        let mouthLeftValue = blendShapes[.mouthLeft]?.floatValue ?? 0
        let mouthRightValue = blendShapes[.mouthRight]?.floatValue ?? 0
        let browDownLeftValue = blendShapes[.browDownLeft]?.floatValue ?? 0
        let browDownRightValue = blendShapes[.browDownRight]?.floatValue ?? 0
        let eyeWideLeftValue = blendShapes[.eyeWideLeft]?.floatValue ?? 0
        let eyeWideRightValue = blendShapes[.eyeWideRight]?.floatValue ?? 0
        
        // Get head pose information
        let headPose = faceAnchor.transform
        let lookAtPoint = faceAnchor.lookAtPoint
        
        // Calculate average values for symmetrical features
        let averageSmile = (smileValue + smileRightValue) / 2
        let averageFrown = (frownValue + frownRightValue) / 2
        let averageBrowOuterUp = (browOuterUpLeftValue + browOuterUpRightValue) / 2
        let averageEyeBlink = (eyeBlinkLeftValue + eyeBlinkRightValue) / 2
        let averageEyeSquint = (eyeSquintLeftValue + eyeSquintRightValue) / 2
        let averageNoseSneer = (noseSneerLeftValue + noseSneerRightValue) / 2
        let averageMouth = (mouthLeftValue + mouthRightValue) / 2
        let averageBrowDown = (browDownLeftValue + browDownRightValue) / 2
        let averageEyeWide = (eyeWideLeftValue + eyeWideRightValue) / 2
        
        // Calculate emotion scores with head pose consideration
        var emotionScores: [EmotionScore] = []
        
        // Happy score calculation with head pose adjustment
        let happyScore = calculateHappyScore(
            smile: averageSmile,
            eyeSquint: averageEyeSquint,
            jawOpen: jawOpenValue,
            cheekPuff: cheekPuffValue,
            headPose: headPose
        )
        emotionScores.append(EmotionScore(emotion: "Happy", score: happyScore))
        
        // Angry score calculation with head pose adjustment
        let angryScore = calculateAngryScore(
            frown: averageFrown,
            browInnerUp: browInnerUpValue,
            eyeSquint: averageEyeSquint,
            browDown: averageBrowDown,
            headPose: headPose
        )
        emotionScores.append(EmotionScore(emotion: "Angry", score: angryScore))
        
        // Sad score calculation with head pose adjustment
        let sadScore = calculateSadScore(
            frown: averageFrown,
            browInnerUp: browInnerUpValue,
            smile: averageSmile,
            mouthPucker: mouthPuckerValue,
            headPose: headPose
        )
        emotionScores.append(EmotionScore(emotion: "Sad", score: sadScore))
        
        // Surprised score calculation with head pose adjustment
        let surprisedScore = calculateSurprisedScore(
            jawOpen: jawOpenValue,
            eyeBlink: averageEyeBlink,
            browOuterUp: averageBrowOuterUp,
            eyeWide: averageEyeWide,
            headPose: headPose
        )
        emotionScores.append(EmotionScore(emotion: "Surprised", score: surprisedScore))
        
        // Disgusted score calculation with head pose adjustment
        let disgustedScore = calculateDisgustedScore(
            eyeSquint: averageEyeSquint,
            noseSneer: averageNoseSneer,
            smile: averageSmile,
            mouthFunnel: mouthFunnelValue,
            headPose: headPose
        )
        emotionScores.append(EmotionScore(emotion: "Disgusted", score: disgustedScore))
        
        // Fearful score calculation with head pose adjustment
        let fearfulScore = calculateFearfulScore(
            browOuterUp: averageBrowOuterUp,
            jawOpen: jawOpenValue,
            smile: averageSmile,
            eyeWide: averageEyeWide,
            headPose: headPose
        )
        emotionScores.append(EmotionScore(emotion: "Fearful", score: fearfulScore))
        
        // Neutral score calculation with head pose adjustment
        let neutralScore = calculateNeutralScore(
            smile: averageSmile,
            frown: averageFrown,
            jawOpen: jawOpenValue,
            browInnerUp: browInnerUpValue,
            mouth: averageMouth,
            headPose: headPose
        )
        emotionScores.append(EmotionScore(emotion: "Neutral", score: neutralScore))
        
        // Find the emotion with the highest confidence score
        if let highestScore = emotionScores.max(by: { $0.score < $1.score }) {
            // Add to history
            emotionHistory.append((emotion: highestScore.emotion, confidence: highestScore.score))
            if emotionHistory.count > maxFrameHistory {
                emotionHistory.removeFirst()
            }
            
            // Calculate temporal average
            let averagedEmotion = calculateTemporalAverage()
            currentEmotion = averagedEmotion.emotion
            emotionConfidence = averagedEmotion.confidence
        } else {
            currentEmotion = "Neutral"
            emotionConfidence = 0.0
        }
    }
    
    private func calculateTemporalAverage() -> (emotion: String, confidence: Double) {
        guard !emotionHistory.isEmpty else {
            return ("Neutral", 0.0)
        }
        
        // Group emotions and calculate weighted average
        var emotionScores: [String: Double] = [:]
        var totalWeight: Double = 0
        
        for (index, entry) in emotionHistory.enumerated() {
            let weight = Double(index + 1) / Double(emotionHistory.count) // More recent frames have higher weight
            emotionScores[entry.emotion, default: 0] += entry.confidence * weight
            totalWeight += weight
        }
        
        // Find the emotion with highest weighted average
        let averagedEmotion = emotionScores.max(by: { $0.value < $1.value })
        return (emotion: averagedEmotion?.key ?? "Neutral",
                confidence: (averagedEmotion?.value ?? 0) / totalWeight)
    }
    
    private func adjustScoreForHeadPose(_ score: Double, headPose: simd_float4x4) -> Double {
        // Extract rotation from head pose matrix
        let rotation = simd_quaternion(headPose)
        
        // Convert quaternion to Euler angles
        let angles = quaternionToEulerAngles(rotation)
        
        // Adjust score based on head orientation
        // Penalize extreme angles
        let pitchPenalty = abs(angles.x) > 0.5 ? 0.2 : 0
        let yawPenalty = abs(angles.y) > 0.5 ? 0.2 : 0
        let rollPenalty = abs(angles.z) > 0.5 ? 0.1 : 0
        
        return max(0, min(1, score * (1 - pitchPenalty - yawPenalty - rollPenalty)))
    }
    
    private func quaternionToEulerAngles(_ q: simd_quatf) -> SIMD3<Float> {
        // Convert quaternion to Euler angles (in radians)
        // Using the standard aerospace sequence (ZYX)
        let qx = q.vector.x
        let qy = q.vector.y
        let qz = q.vector.z
        let qw = q.vector.w
        
        // Roll (x-axis rotation)
        let sinr_cosp = 2 * (qw * qx + qy * qz)
        let cosr_cosp = 1 - 2 * (qx * qx + qy * qy)
        let roll = atan2(sinr_cosp, cosr_cosp)
        
        // Pitch (y-axis rotation)
        let sinp = 2 * (qw * qy - qz * qx)
        let pitch: Float
        if abs(sinp) >= 1 {
            pitch = copysign(.pi / 2, sinp) // Use 90 degrees if out of range
        } else {
            pitch = asin(sinp)
        }
        
        // Yaw (z-axis rotation)
        let siny_cosp = 2 * (qw * qz + qx * qy)
        let cosy_cosp = 1 - 2 * (qy * qy + qz * qz)
        let yaw = atan2(siny_cosp, cosy_cosp)
        
        return SIMD3<Float>(roll, pitch, yaw)
    }
    
    private func calculateHappyScore(smile: Float, eyeSquint: Float, jawOpen: Float, cheekPuff: Float, headPose: simd_float4x4) -> Double {
        let baseScore = Double(smile) * 1.2
        let eyeSquintPenalty = Double(eyeSquint) * 0.2
        let jawOpenPenalty = Double(jawOpen) * 0.1
        let cheekPuffBonus = Double(cheekPuff) * 0.3
        let rawScore = max(0, min(1, baseScore - eyeSquintPenalty - jawOpenPenalty + cheekPuffBonus))
        return adjustScoreForHeadPose(rawScore, headPose: headPose)
    }
    
    private func calculateAngryScore(frown: Float, browInnerUp: Float, eyeSquint: Float, browDown: Float, headPose: simd_float4x4) -> Double {
        let baseScore = Double(frown) * 1.2
        let browBonus = Double(browInnerUp) * 0.4
        let eyeSquintBonus = Double(eyeSquint) * 0.3
        let browDownBonus = Double(browDown) * 0.3
        let rawScore = max(0, min(1, baseScore + browBonus + eyeSquintBonus + browDownBonus))
        return adjustScoreForHeadPose(rawScore, headPose: headPose)
    }
    
    private func calculateSadScore(frown: Float, browInnerUp: Float, smile: Float, mouthPucker: Float, headPose: simd_float4x4) -> Double {
        let baseScore = Double(frown) * 1.2
        let browPenalty = Double(browInnerUp) * 0.2
        let smilePenalty = Double(smile) * 0.3
        let mouthPuckerBonus = Double(mouthPucker) * 0.3
        let rawScore = max(0, min(1, baseScore - browPenalty - smilePenalty + mouthPuckerBonus))
        return adjustScoreForHeadPose(rawScore, headPose: headPose)
    }
    
    private func calculateSurprisedScore(jawOpen: Float, eyeBlink: Float, browOuterUp: Float, eyeWide: Float, headPose: simd_float4x4) -> Double {
        let baseScore = Double(jawOpen) * 1.2
        let browBonus = Double(browOuterUp) * 0.4
        let eyeBlinkPenalty = Double(eyeBlink) * 0.1
        let eyeWideBonus = Double(eyeWide) * 0.3
        let rawScore = max(0, min(1, baseScore + browBonus - eyeBlinkPenalty + eyeWideBonus))
        return adjustScoreForHeadPose(rawScore, headPose: headPose)
    }
    
    private func calculateDisgustedScore(eyeSquint: Float, noseSneer: Float, smile: Float, mouthFunnel: Float, headPose: simd_float4x4) -> Double {
        let baseScore = Double(eyeSquint) * 1.2
        let noseSneerBonus = Double(noseSneer) * 0.4
        let smilePenalty = Double(smile) * 0.3
        let mouthFunnelBonus = Double(mouthFunnel) * 0.3
        let rawScore = max(0, min(1, baseScore + noseSneerBonus - smilePenalty + mouthFunnelBonus))
        return adjustScoreForHeadPose(rawScore, headPose: headPose)
    }
    
    private func calculateFearfulScore(browOuterUp: Float, jawOpen: Float, smile: Float, eyeWide: Float, headPose: simd_float4x4) -> Double {
        let baseScore = Double(browOuterUp) * 1.2
        let jawOpenBonus = Double(jawOpen) * 0.3
        let smilePenalty = Double(smile) * 0.3
        let eyeWideBonus = Double(eyeWide) * 0.3
        let rawScore = max(0, min(1, baseScore + jawOpenBonus - smilePenalty + eyeWideBonus))
        return adjustScoreForHeadPose(rawScore, headPose: headPose)
    }
    
    private func calculateNeutralScore(smile: Float, frown: Float, jawOpen: Float, browInnerUp: Float, mouth: Float, headPose: simd_float4x4) -> Double {
        let maxExpression = max(smile, max(frown, max(jawOpen, max(browInnerUp, mouth))))
        let neutralScore = 1.0 - Double(maxExpression)
        let rawScore = maxExpression < 0.1 ? neutralScore : neutralScore * 0.5
        return adjustScoreForHeadPose(rawScore, headPose: headPose)
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
