import UIKit
@preconcurrency import AVFoundation

public enum ScannerError: LocalizedError, Sendable, Equatable {
    case cameraPermissionDenied
    case cameraPermissionRestricted
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case unsupportedMetadataTypes([String])
    case configurationFailed(String)
    case sessionInterrupted
    case sessionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied: return "相机访问被拒绝，请在系统设置中允许访问相机。"
        case .cameraPermissionRestricted: return "此设备限制了相机访问。"
        case .cameraUnavailable: return "此设备没有可用的相机。"
        case .cannotAddInput: return "无法连接相机输入。"
        case .cannotAddOutput: return "无法创建二维码与条形码识别输出。"
        case .unsupportedMetadataTypes(let types):
            return types.isEmpty ? "请至少配置一种支持的条码类型。" : "相机不支持所请求的条码类型：\(types.joined(separator: ", "))。"
        case .configurationFailed(let message): return "相机配置失败：\(message)"
        case .sessionInterrupted: return "相机暂时被其他任务占用，恢复后将继续扫描。"
        case .sessionFailed(let message): return "相机运行失败：\(message)"
        }
    }
}

/// A single-code scanner for a standard navigation controller.
public final class ScannerVC: UIViewController {
    public var animationStyle: ScanAnimationStyle = .default {
        didSet { scanView.animationStyle = animationStyle }
    }
    public var scannerColor: UIColor = .red {
        didSet { scanView.color = scannerColor }
    }
    public var scannerTips = "" {
        didSet { scanView.tips = scannerTips }
    }
    public var scanRegion: ScanRegion = .scanFrame {
        didSet {
            scanView.scanRegion = scanRegion
            if isViewLoaded { scanView.layoutIfNeeded() }
        }
    }
    public var metadataTypes = AVMetadataObject.ObjectType.supportedBarcodeTypes {
        didSet {
            guard Set(metadataTypes) != Set(oldValue) else { return }
            captureGeneration &+= 1
            synchronizeCapture()
        }
    }
    /// Called once per run on the main thread. The caller controls navigation.
    public var onScan: ((String) -> Void)?
    public var onError: ((Error) -> Void)?

    private let scanView = ScanView(frame: .zero)
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let torchButton = UIButton(type: .custom)
    private var captureController: CameraCaptureController?
    private var updatePreviewRotation: (() -> Void)?
    private var previewRotationObservation: NSKeyValueObservation?
    private var previewRotationDeviceID: String?
    private var isVisible = false
    private var wantsScanning = true
    private var isCameraRunning = false
    private var isTorchAvailable = false
    private var torchMode: TorchMode = .off
    private var torchSuggested = false
    private var captureGeneration: UInt64 = 0
    private var regionOfInterest = CGRect.zero

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = title ?? "扫一扫"
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        scanView.animationStyle = animationStyle
        scanView.color = scannerColor
        scanView.tips = scannerTips
        scanView.scanRegion = scanRegion
        scanView.onScanRectChange = { [weak self] in self?.updateCaptureGeometry() }
        scanView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scanView.frame = view.bounds
        view.addSubview(scanView)
        setupTorchButton()
        NotificationCenter.default.addObserver(self, selector: #selector(sceneActivityChanged),
                                               name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sceneActivityChanged),
                                               name: UIScene.willDeactivateNotification, object: nil)
        prepareCapture()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        restartScanning()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        pauseCapture()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = view.bounds
        CATransaction.commit()
        scanView.frame = view.bounds
        scanView.layoutIfNeeded()
        updateCaptureGeometry()
    }

    deinit {
        captureController?.shutdown()
        NotificationCenter.default.removeObserver(self)
    }

    /// Start a fresh run after a result when keeping the scanner on screen.
    public func restartScanning() {
        wantsScanning = true
        captureGeneration &+= 1
        synchronizeCapture()
    }

    private var shouldCapture: Bool {
        isVisible && wantsScanning && viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive
    }

    private func prepareCapture() {
        let types = metadataTypes
        let handleEvent: @MainActor @Sendable (CameraEvent) -> Void = { [weak self] event in
            self?.handle(event)
        }
        let install: @MainActor @Sendable (CameraCaptureController) -> Void = { [weak self] controller in
            guard let self else { return }
            captureController = controller
            previewLayer.session = controller.session
            updateCaptureGeometry()
            synchronizeCapture()
        }
        // Session and output construction can block, even before configuring or starting them.
        DispatchQueue.global(qos: .userInitiated).async {
            let controller = CameraCaptureController(metadataTypes: types, handleEvent: handleEvent)
            DispatchQueue.main.async { install(controller) }
        }
    }

    @objc private func sceneActivityChanged(_ notification: Notification) {
        guard isVisible, let scene = notification.object as? UIScene,
              scene === viewIfLoaded?.window?.windowScene else { return }
        if notification.name == UIScene.willDeactivateNotification {
            pauseCapture()
        } else {
            synchronizeCapture()
        }
    }

    private func pauseCapture() {
        captureGeneration &+= 1
        captureController?.update(metadataTypes: metadataTypes, regionOfInterest: regionOfInterest,
                                  running: false, generation: captureGeneration)
        scanView.stopAnimation()
        torchButton.isHidden = true
    }

    private func synchronizeCapture() {
        captureController?.update(metadataTypes: metadataTypes, regionOfInterest: regionOfInterest,
                                  running: shouldCapture, generation: captureGeneration)
        updateTorchButton()
    }

    private func setupTorchButton() {
        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.setImage(torchMode.image, for: .normal)
        torchButton.accessibilityLabel = "打开手电筒"
        torchButton.isHidden = true
        torchButton.addTarget(self, action: #selector(toggleTorch), for: .touchUpInside)
        view.addSubview(torchButton)
        NSLayoutConstraint.activate([
            torchButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            torchButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            torchButton.widthAnchor.constraint(equalToConstant: 44),
            torchButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func toggleTorch() { captureController?.toggleTorch() }

    private func updateCaptureGeometry() {
        if #available(iOS 17, *) {
            updatePreviewRotation?()
        } else if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            let orientation = viewIfLoaded?.window?.windowScene?.interfaceOrientation ?? .portrait
            let videoOrientation: AVCaptureVideoOrientation
            switch orientation {
            case .landscapeLeft: videoOrientation = .landscapeLeft
            case .landscapeRight: videoOrientation = .landscapeRight
            case .portraitUpsideDown: videoOrientation = .portraitUpsideDown
            default: videoOrientation = .portrait
            }
            if connection.videoOrientation != videoOrientation { connection.videoOrientation = videoOrientation }
        }
        let layerRect = scanView.convert(scanView.scanRect, to: view)
        let region = previewLayer.metadataOutputRectConverted(fromLayerRect: layerRect)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let valid = !region.isNull && !region.isEmpty
            && region.origin.x.isFinite && region.origin.y.isFinite
            && region.width.isFinite && region.height.isFinite
        let effectiveRegion = valid ? region : .zero
        guard regionOfInterest != effectiveRegion else { return }
        regionOfInterest = effectiveRegion
        captureGeneration &+= 1
        synchronizeCapture()
    }

    private func configurePreviewRotation(deviceID: String) {
        guard #available(iOS 17, *), previewRotationDeviceID != deviceID,
              let device = AVCaptureDevice(uniqueID: deviceID) else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        previewRotationDeviceID = deviceID
        // The closure owns the newer coordinator without an availability-erased stored property.
        updatePreviewRotation = { [weak previewLayer] in
            guard let connection = previewLayer?.connection else { return }
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle {
                connection.videoRotationAngle = angle
            }
        }
        previewRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview,
                                                         options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in self?.updateCaptureGeometry() }
        }
        updateCaptureGeometry()
    }

    private func handle(_ event: CameraEvent) {
        guard event.generation == captureGeneration else { return }
        switch event.payload {
        case .cameraDevice(let deviceID):
            configurePreviewRotation(deviceID: deviceID)
        case .running(let running):
            isCameraRunning = running
            if running && shouldCapture {
                scanView.startAnimation()
                view.setNeedsLayout()
            } else {
                scanView.stopAnimation()
            }
            updateTorchButton()
        case .result(let code):
            guard shouldCapture else { return }
            wantsScanning = false
            scanView.stopAnimation()
            updateTorchButton()
            onScan?(code)
        case .failure(let error):
            guard isVisible else { return }
            onError?(error)
        case .torchSuggestion(let suggested):
            torchSuggested = suggested
            updateTorchButton()
        case .torch(let mode, let available):
            torchMode = mode
            isTorchAvailable = available
            torchButton.setImage(mode.image, for: .normal)
            torchButton.accessibilityLabel = mode == .on ? "关闭手电筒" : "打开手电筒"
            torchButton.accessibilityValue = mode == .on ? "已开启" : "已关闭"
            updateTorchButton()
        }
    }

    private func updateTorchButton() {
        torchButton.isHidden = !shouldCapture || !isCameraRunning || !isTorchAvailable || (!torchSuggested && torchMode == .off)
    }
}

private struct CameraEvent: Sendable {
    let generation: UInt64
    let payload: Payload

    enum Payload: Sendable {
        case cameraDevice(String)
        case running(Bool)
        case result(String)
        case failure(ScannerError)
        case torchSuggestion(Bool)
        case torch(TorchMode, available: Bool)
    }
}

/// AVFoundation objects and mutable capture state are owned by this serial queue.
private final class CameraCaptureController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.swiftscankit.capture", qos: .userInitiated)
    private let handleEvent: @MainActor @Sendable (CameraEvent) -> Void
    private let metadataOutput = AVCaptureMetadataOutput()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var barcodeDecoder: BarcodeDecoder?
    private var barcodeConfiguration: BarcodeDecoder.Configuration?
    private var barcodeDecodeInFlight = false
    private var lastBarcodeDecodeTime = -Double.infinity
    private var captureDevice: AVCaptureDevice?
    private var torchObservation: NSKeyValueObservation?
    private var requestedTypes: [AVMetadataObject.ObjectType]
    private var configured = false
    private var wantsRunning = false
    private var deliveredResult = false
    private var requestingAuthorization = false
    private var lastReportedError: ScannerError?
    private var lastReportedRunning: Bool?
    private var generation: UInt64 = 0
    private var regionOfInterest = CGRect.zero
    private var lastBrightnessTime = -Double.infinity
    private var torchSuggested = false

    init(metadataTypes: [AVMetadataObject.ObjectType], handleEvent: @escaping @MainActor @Sendable (CameraEvent) -> Void) {
        requestedTypes = metadataTypes
        self.handleEvent = handleEvent
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(runningStateChanged), name: AVCaptureSession.didStartRunningNotification, object: session)
        center.addObserver(self, selector: #selector(runningStateChanged), name: AVCaptureSession.didStopRunningNotification, object: session)
        center.addObserver(self, selector: #selector(runtimeError), name: AVCaptureSession.runtimeErrorNotification, object: session)
        center.addObserver(self, selector: #selector(interruptionBegan), name: AVCaptureSession.wasInterruptedNotification, object: session)
        center.addObserver(self, selector: #selector(interruptionEnded), name: AVCaptureSession.interruptionEndedNotification, object: session)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func shutdown() {
        sessionQueue.async { [self] in
            wantsRunning = false
            stopSession()
            metadataOutput.setMetadataObjectsDelegate(nil, queue: nil)
            for output in session.outputs {
                (output as? AVCaptureVideoDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
            }
            torchObservation = nil
            NotificationCenter.default.removeObserver(self)
        }
    }

    func update(metadataTypes types: [AVMetadataObject.ObjectType], regionOfInterest region: CGRect,
                running: Bool, generation requestedGeneration: UInt64) {
        sessionQueue.async { [self] in
            requestedTypes = types
            if regionOfInterest != region {
                regionOfInterest = region
                if configured { metadataOutput.rectOfInterest = region }
            }
            if generation != requestedGeneration {
                generation = requestedGeneration
                deliveredResult = false
                lastReportedError = nil
                lastReportedRunning = nil
                emit(.torchSuggestion(torchSuggested))
            }
            wantsRunning = running
            updateRunningState()
        }
    }

    func toggleTorch() {
        sessionQueue.async { [self] in
            guard wantsRunning, session.isRunning else { return }
            applyTorchMode(captureDevice?.torchMode == .on ? .off : .on, reportFailure: true)
        }
    }

    private func updateRunningState() {
        guard wantsRunning && !deliveredResult else { stopSession(); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard !requestingAuthorization else { return }
            requestingAuthorization = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                guard let self else { return }
                self.sessionQueue.async {
                    self.requestingAuthorization = false
                    self.updateRunningState()
                }
            }
            return
        case .denied: report(.cameraPermissionDenied); return
        case .restricted: report(.cameraPermissionRestricted); return
        @unknown default: report(.cameraPermissionRestricted); return
        }
        guard !session.isInterrupted else { publishSessionState(); return }
        do {
            if !configured { try configureSession() }
            else {
                try applyMetadataTypes()
                updateVideoOutput()
            }
            if !session.isRunning { session.startRunning() }
            publishSessionState()
            if session.isRunning {
                lastReportedError = nil
            } else if !session.isInterrupted {
                report(.sessionFailed("相机会话未能启动。"))
            }
        } catch let error as ScannerError {
            stopSession()
            report(error)
        } catch {
            stopSession()
            report(.configurationFailed(error.localizedDescription))
        }
    }

    private func configureSession() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video) else { throw ScannerError.cameraUnavailable }
        let input: AVCaptureDeviceInput
        do { input = try AVCaptureDeviceInput(device: device) }
        catch { throw ScannerError.configurationFailed(error.localizedDescription) }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        videoOutput = nil
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        else if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        guard session.canAddInput(input) else { throw ScannerError.cannotAddInput }
        session.addInput(input)
        guard session.canAddOutput(metadataOutput) else { throw ScannerError.cannotAddOutput }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: sessionQueue)
        captureDevice = device
        try applyMetadataTypes()
        metadataOutput.rectOfInterest = regionOfInterest
        try configureDevice(device)
        torchObservation = device.observe(\.isTorchAvailable, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            self.sessionQueue.async { self.publishTorchState() }
        }
        updateVideoOutput()
        configured = true
    }

    private func applyMetadataTypes() throws {
        let requested = Set(requestedTypes)
        let machineTypes = Set(AVMetadataObject.ObjectType.supportedBarcodeTypes)
        let supported = metadataOutput.availableMetadataObjectTypes.filter {
            requested.contains($0) && machineTypes.contains($0)
        }
        if metadataOutput.metadataObjectTypes != supported {
            metadataOutput.metadataObjectTypes = supported
            if BarcodeDecoder.supportsAny(of: supported) {
                let decoder = barcodeDecoder ?? BarcodeDecoder()
                barcodeDecoder = decoder
                barcodeConfiguration = decoder.configuration(for: supported)
            } else {
                barcodeConfiguration = nil
            }
        }
        guard !supported.isEmpty else { throw ScannerError.unsupportedMetadataTypes(requestedTypes.map(\.rawValue)) }
    }

    private func updateVideoOutput() {
        let needed = captureDevice?.hasTorch == true || barcodeConfiguration != nil
        guard needed != (videoOutput != nil) else { return }
        // Initial setup already owns a configuration transaction.
        if configured { session.beginConfiguration() }
        defer { if configured { session.commitConfiguration() } }
        if let output = videoOutput {
            output.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(output)
            videoOutput = nil
            return
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [:]
        guard session.canAddOutput(output) else {
            if captureDevice?.hasTorch == true {
                torchSuggested = true
                emit(.torchSuggestion(true))
            }
            return
        }
        session.addOutput(output)
        // Keep metadata ROI and pixel buffers in the same natural sensor coordinates.
        // Preview rotation is independent and must never rotate these buffers.
        if let connection = output.connection(with: .video) {
            if #available(iOS 17, *) {
                if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .landscapeRight
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput = output
    }

    private func decodeBarcode(in sampleBuffer: CMSampleBuffer) {
        guard !barcodeDecodeInFlight, let decoder = barcodeDecoder, let configuration = barcodeConfiguration,
              !regionOfInterest.isEmpty, !regionOfInterest.isNull else { return }
        let now = CACurrentMediaTime()
        guard now - lastBarcodeDecodeTime >= 0.5,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastBarcodeDecodeTime = now
        barcodeDecodeInFlight = true
        let requestedGeneration = generation
        let region = regionOfInterest
        decoder.decode(pixelBuffer, region: region, configuration: configuration) { [weak self] result in
            guard let self else { return }
            self.sessionQueue.async {
                self.barcodeDecodeInFlight = false
                guard self.generation == requestedGeneration,
                      let result, self.metadataOutput.metadataObjectTypes.contains(result.type) else { return }
                self.finish(result.value)
            }
        }
    }

    private func finish(_ code: String) {
        guard wantsRunning, !deliveredResult, session.isRunning, !session.isInterrupted,
              !regionOfInterest.isEmpty, !code.isEmpty else { return }
        deliveredResult = true
        wantsRunning = false
        emit(.result(code))
        stopSession()
    }

    private func configureDevice(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
    }

    private func stopSession() {
        applyTorchMode(.off)
        if session.isRunning { session.stopRunning() }
        publishSessionState()
    }

    private func applyTorchMode(_ mode: TorchMode, reportFailure: Bool = false) {
        guard let device = captureDevice, device.hasTorch else { return }
        guard device.isTorchAvailable, device.isTorchModeSupported(mode.captureTorchMode) else {
            publishTorchState()
            return
        }
        do {
            if device.torchMode != mode.captureTorchMode {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.torchMode = mode.captureTorchMode
            }
            publishTorchState()
        } catch {
            if reportFailure { report(.configurationFailed(error.localizedDescription)) }
        }
    }

    private func publishTorchState() {
        guard let device = captureDevice else { return }
        emit(.torch(device.torchMode == .on ? .on : .off, available: device.hasTorch && device.isTorchAvailable))
    }

    private func publishSessionState() {
        let running = session.isRunning && !session.isInterrupted
        guard lastReportedRunning != running else { return }
        lastReportedRunning = running
        if running, let device = captureDevice {
            emit(.cameraDevice(device.uniqueID))
            publishTorchState()
        }
        emit(.running(running))
    }

    private func report(_ error: ScannerError) {
        guard lastReportedError != error else { return }
        lastReportedError = error
        emit(.failure(error))
    }

    private func emit(_ payload: CameraEvent.Payload) {
        let event = CameraEvent(generation: generation, payload: payload)
        DispatchQueue.main.async { [handleEvent] in handleEvent(event) }
    }

    @objc private func runningStateChanged(_ notification: Notification) {
        sessionQueue.async { [self] in publishSessionState() }
    }

    @objc private func runtimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        let wasReset = error?.code == .mediaServicesWereReset
        let message = error?.localizedDescription ?? "未知相机错误。"
        sessionQueue.async { [self] in
            if wasReset && wantsRunning && !deliveredResult {
                updateRunningState()
            } else if wantsRunning {
                stopSession()
                report(.sessionFailed(message))
            } else {
                publishSessionState()
            }
        }
    }

    @objc private func interruptionBegan(_ notification: Notification) {
        sessionQueue.async { [self] in
            applyTorchMode(.off)
            publishSessionState()
            if wantsRunning && !deliveredResult { report(.sessionInterrupted) }
        }
    }

    @objc private func interruptionEnded(_ notification: Notification) {
        sessionQueue.async { [self] in updateRunningState() }
    }
}

extension CameraCaptureController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard wantsRunning, !deliveredResult, let enabledTypes = output.metadataObjectTypes else { return }
        guard let code = metadataObjects.lazy.compactMap({ object -> String? in
            guard let code = object as? AVMetadataMachineReadableCodeObject,
                  enabledTypes.contains(code.type), let value = code.stringValue, !value.isEmpty else { return nil }
            return value
        }).first else { return }
        finish(code)
    }
}

extension CameraCaptureController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard output === videoOutput, wantsRunning, !deliveredResult else { return }
        decodeBarcode(in: sampleBuffer)
        guard captureDevice?.hasTorch == true else { return }
        let timestamp = sampleBuffer.presentationTimeStamp.seconds
        guard timestamp.isFinite, timestamp < lastBrightnessTime || timestamp - lastBrightnessTime >= 0.5 else { return }
        lastBrightnessTime = timestamp
        let exif = sampleBuffer.attachments[kCGImagePropertyExifDictionary as String]?.value as? [String: Any]
        let brightness = exif?[kCGImagePropertyExifBrightnessValue as String] as? NSNumber
        // Missing metering information keeps the manual torch accessible.
        let suggested: Bool
        if let brightness, brightness.doubleValue.isFinite {
            suggested = brightness.doubleValue < (torchSuggested ? -0.5 : -1)
        } else {
            suggested = true
        }
        guard suggested != torchSuggested else { return }
        torchSuggested = suggested
        emit(.torchSuggestion(suggested))
    }
}
