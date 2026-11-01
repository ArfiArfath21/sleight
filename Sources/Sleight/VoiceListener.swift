import AVFoundation
import AppKit
import Speech
import SleightCore

/// Listens through the microphone with on-device speech recognition and turns
/// "hey Sleight, …" into intents. Nothing is sent off the Mac.
///
/// One recognition task runs at a time. It's thrown away and replaced after
/// every command (so an old wake phrase can't fire twice), after a long stretch
/// of unrelated talk, and after errors.
final class VoiceListener {
    enum State: Equatable {
        case off
        case waiting               // listening for "hey Sleight"
        case listening(String)     // heard the wake phrase, here's the command so far
        case unavailable(String)
    }

    var config = SleightConfig()
    /// Resting: only "wake up" is acted on.
    var resting = false
    var onState: ((State) -> Void)?
    var onIntent: ((VoiceIntent) -> Void)?
    /// Something to tell the user briefly ("Didn't catch that").
    var onMessage: ((String) -> Void)?
    /// Extra words to help the recogniser (app names).
    var vocabulary: () -> [String] = { [] }
    /// Menu commands of the app in front (titles), also accepted as commands.
    var menuTitles: () -> [String] = { [] }

    private(set) var state: State = .off { didSet { if state != oldValue { onState?(state) } } }
    private(set) var running = false
    /// Listen for a command straight away once started (voice just turned on).
    var listenOnStart = false
    private var starting = false

    private let audio = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let requestLock = NSLock()
    private var task: SFSpeechRecognitionTask?
    private var taskStarted = 0.0
    private var generation = 0

    /// Wake phrase heard (or push-to-talk) and waiting for the command until then.
    private var armedUntil: Double?
    private var pushToTalk = false
    /// Started by push-to-talk alone: stop again after one command.
    private var oneShot = false
    private var command = ""
    /// Dictation ("type …") can run over several recogniser segments: the
    /// recogniser starts afresh after a pause, so earlier segments are kept here.
    private var dictationBase = ""
    private var segment = ""
    private var settle: DispatchWorkItem?
    private var timeout: DispatchWorkItem?
    private var failures = 0

    // MARK: Start / stop

    /// Starts listening (asking for permission the first time).
    func start(oneShot: Bool = false, completion: ((Bool) -> Void)? = nil) {
        if running { completion?(true); return }
        guard !starting else { return }
        starting = true
        Self.authorize { [weak self] error in
            guard let self else { return }
            self.starting = false
            if let error {
                self.state = .unavailable(error)
                completion?(false)
                return
            }
            do {
                try self.startAudio()
                self.oneShot = oneShot
                self.running = true
                self.failures = 0
                self.state = .waiting
                self.newTask()
                if self.listenOnStart {
                    self.listenOnStart = false
                    self.pushToTalk = true
                    self.arm()
                }
                completion?(true)
            } catch {
                self.state = .unavailable("Microphone unavailable")
                completion?(false)
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        oneShot = false
        disarm()
        endTask()
        audio.inputNode.removeTap(onBus: 0)
        audio.stop()
        state = .off
    }

    /// Push-to-talk: listen for one command now, no wake phrase needed.
    func listenNow() {
        if !running {
            start(oneShot: true) { [weak self] ok in if ok { self?.listenNow() } }
            return
        }
        newTask()
        pushToTalk = true
        arm()
    }

    private static func authorize(_ done: @escaping (String?) -> Void) {
        func main(_ e: String?) { DispatchQueue.main.async { done(e) } }
        AVCaptureDevice.requestAccess(for: .audio) { micOK in
            guard micOK else { return main("Microphone access is off (System Settings → Privacy → Microphone)") }
            let denied = "Speech recognition is off (System Settings → Privacy → Speech Recognition)"
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: main(nil)
            case .notDetermined:
                SFSpeechRecognizer.requestAuthorization { status in main(status == .authorized ? nil : denied) }
            default: main(denied)
            }
        }
    }

    private func startAudio() throws {
        let r = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let r, r.isAvailable else { throw NSError(domain: "Sleight", code: 1) }
        recognizer = r
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.requestLock.lock()
            self.request?.append(buffer)
            self.requestLock.unlock()
        }
        audio.prepare()
        try audio.start()
    }

    // MARK: Recognition tasks

    private func newTask() {
        endTask()
        guard running, let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        // Punctuation and capitals for dictation; commands ignore them.
        req.addsPunctuation = true
        // Bias the recogniser towards what makes sense right now: the wake word,
        // commands, app names, and the menu commands of the app in front.
        req.contextualStrings = [config.wakeWord.title, config.wakeWord.phrase]
            + VoiceCommands.phrases.compactMap { $0.1.first }
            + Array(menuTitles().prefix(60)) + Array(vocabulary().prefix(60))
        requestLock.lock(); request = req; requestLock.unlock()
        generation += 1
        let gen = generation
        taskStarted = CACurrentMediaTime()
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                if let result {
                    self.failures = 0
                    self.heard(result.bestTranscription.formattedString, final: result.isFinal)
                }
                if error != nil || result?.isFinal == true { self.restartSoon(after: error) }
            }
        }
    }

    private func endTask() {
        generation += 1
        requestLock.lock()
        request?.endAudio()
        request = nil
        requestLock.unlock()
        task?.cancel()
        task = nil
    }

    private func restartSoon(after error: Error?) {
        guard running else { return }
        if error != nil { failures += 1 }
        // Silence ends tasks with an error now and then; back off if it keeps failing.
        let delay = error == nil ? 0 : min(0.2 * Double(failures), 3)
        if failures > 20 { state = .unavailable("Speech recognition keeps failing"); stop(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.running else { return }
            let keepArmed = self.armedUntil != nil
            self.newTask()
            if !keepArmed { self.disarm() }
        }
    }

    // MARK: Transcript → command

    private func heard(_ text: String, final: Bool) {
        // `defaults write com.arfiarfath21.sleight voiceDebug -bool true` logs transcripts, for tuning.
        if UserDefaults.standard.bool(forKey: "voiceDebug") {
            NSLog("Sleight voice heard: \(text)\(final ? " (final)" : "")")
        }
        if armedUntil == nil {
            guard let wake = VoiceCommands.wake(in: text, word: config.wakeWord) else {
                // Unrelated talk: start fresh now and then so transcripts stay short.
                if text.count > 240 || CACurrentMediaTime() - taskStarted > 50 { newTask() }
                return
            }
            arm()
            update(wake.command, final: final)
        } else {
            // After a restart the transcript no longer starts with the wake phrase.
            let t = VoiceCommands.wake(in: text, word: config.wakeWord)?.command
                ?? VoiceCommands.dropLeadingName(text, word: config.wakeWord)
            if isDictating, isNewSegment(t) {
                dictationBase = command
            }
            segment = t
            update(dictationBase.isEmpty ? t : dictationBase + " " + t, final: final)
        }
    }

    private var isDictating: Bool { VoiceCommands.startsDictation(command) }

    /// The recogniser dropped what it had and began again (after a pause), as
    /// opposed to revising its guess, which keeps the start and the length.
    private func isNewSegment(_ t: String) -> Bool {
        guard !segment.isEmpty, !t.isEmpty else { return false }
        let first = { (s: String) in VoiceCommands.normalize(s).split(separator: " ").first.map(String.init) ?? "" }
        return first(t) != first(segment) && t.count < segment.count / 2 + 4
    }

    private func arm() {
        command = ""
        state = .listening("")
        keepListening(for: config.voiceListenWindow)
    }

    /// (Re)starts the wait for the command.
    private func keepListening(for seconds: Double) {
        armedUntil = CACurrentMediaTime() + seconds
        timeout?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.timedOut() }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func disarm() {
        armedUntil = nil
        pushToTalk = false
        command = ""
        dictationBase = ""
        segment = ""
        settle?.cancel(); settle = nil
        timeout?.cancel(); timeout = nil
        if running, case .listening = state { state = .waiting }
    }

    private func update(_ text: String, final: Bool) {
        command = text
        let intent = parse(text)
        let dictating = VoiceCommands.startsDictation(text)
        // Dictation waits for a longer silence: people pause mid-sentence.
        let pause = dictating ? max(config.voiceDictationPause, config.voiceSettle) : config.voiceSettle
        // Still talking: don't time out mid-sentence.
        if !text.isEmpty, let until = armedUntil, until - CACurrentMediaTime() < pause + 1.5 {
            keepListening(for: pause + 1.5)
        }
        state = .listening(text)
        settle?.cancel()
        guard intent != nil else { return }
        // A final result ends a command, but not dictation: more may follow the pause.
        if final, !dictating { commit(); return }
        // Wait for the words to stop changing ("switch to" → "switch to Claude").
        let work = DispatchWorkItem { [weak self] in self?.commit() }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + pause, execute: work)
    }

    private func commit() {
        guard let intent = parse(command) else { return }
        let wasOneShot = oneShot
        disarm()
        newTask()
        state = .waiting
        if resting, intent != .wake, intent != .cancel {
            onMessage?("Resting · say \"\(config.wakeWord.phrase), wake up\"")
        } else {
            onIntent?(intent)
        }
        if wasOneShot { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.stopIfOneShot() } }
    }

    private func parse(_ text: String) -> VoiceIntent? { VoiceCommands.parse(text, menu: menuTitles()) }

    /// The app in front changed: pick up its menu words, unless mid-command.
    func contextChanged() {
        if running, armedUntil == nil { newTask() }
    }

    private func timedOut() {
        let said = command
        disarm()
        newTask()
        state = .waiting
        if !said.isEmpty { onMessage?("Didn't catch \"\(said)\"") }
        if oneShot { stopIfOneShot() }
    }

    private func stopIfOneShot() {
        guard oneShot, armedUntil == nil else { return }
        stop()
    }

    // MARK: Offline check

    /// Transcribes every audio file in `folder` with the same settings as live
    /// listening and prints `file<TAB>transcript`. A file named `word__…` gets
    /// `word` as its contextual hint, like the live wake word.
    static func transcribe(folder: URL, done: @escaping () -> Void) {
        authorize { error in
            if let error { print("error: \(error)"); done(); return }
            guard let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else { done(); return }
            let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { ["aiff", "wav", "m4a"].contains($0.pathExtension) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            var remaining = files[...]
            func next() {
                guard let f = remaining.popFirst() else { done(); return }
                let req = SFSpeechURLRecognitionRequest(url: f)
                if r.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
                req.addsPunctuation = false
                let hint = f.deletingPathExtension().lastPathComponent.components(separatedBy: "__").first ?? ""
                req.contextualStrings = [hint, "hey " + hint] + VoiceCommands.phrases.compactMap { $0.1.first }
                var printed = false
                r.recognitionTask(with: req) { result, error in
                    guard !printed else { return }
                    if let result, result.isFinal {
                        printed = true
                        print("\(f.lastPathComponent)\t\(result.bestTranscription.formattedString)")
                        fflush(stdout)
                        DispatchQueue.main.async { next() }
                    } else if error != nil {
                        printed = true
                        print("\(f.lastPathComponent)\t")
                        fflush(stdout)
                        DispatchQueue.main.async { next() }
                    }
                }
            }
            next()
        }
    }
}
