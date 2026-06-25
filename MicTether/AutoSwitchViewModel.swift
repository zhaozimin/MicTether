import Foundation
import Combine
import CoreAudio

@MainActor
class AutoSwitchViewModel: ObservableObject {

    // MARK: - App 内部属性
    @Published var inputs: [AudioDevice] = []
    @Published var outputs: [AudioDevice] = []

    @Published var currentInput: AudioDevice?
    @Published var currentOutput: AudioDevice?

    @Published var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
            if isEnabled {
                applyRoutingPolicyImmediately()
            } else {
                cancelPendingWork()
                isUsingTargetInput = currentInput?.uid == targetInputUID
                isUsingTargetOutput = currentOutput?.uid == targetOutputUID
            }
        }
    }

    // MARK: - 持久化的目标设备 (要被「记住」的设备 UID)
    @Published var targetInputUID: String? {
        didSet {
            UserDefaults.standard.set(targetInputUID, forKey: "targetInputUID")
            applyRoutingPolicyImmediately()
        }
    }
    @Published var targetOutputUID: String? {
        didSet {
            UserDefaults.standard.set(targetOutputUID, forKey: "targetOutputUID")
            applyRoutingPolicyImmediately()
        }
    }

    // MARK: - 显式配置的回退设备 UID
    @Published var preferredFallbackInputUID: String? {
        didSet {
            UserDefaults.standard.set(preferredFallbackInputUID, forKey: "preferredFallbackInputUID")
            applyRoutingPolicyImmediately()
        }
    }
    @Published var preferredFallbackOutputUID: String? {
        didSet {
            UserDefaults.standard.set(preferredFallbackOutputUID, forKey: "preferredFallbackOutputUID")
            applyRoutingPolicyImmediately()
        }
    }

    // MARK: - 自动记忆的回退设备 UID
    @Published private(set) var learnedFallbackInputUID: String? {
        didSet { UserDefaults.standard.set(learnedFallbackInputUID, forKey: "fallbackInputUID") }
    }
    @Published private(set) var learnedFallbackOutputUID: String? {
        didSet { UserDefaults.standard.set(learnedFallbackOutputUID, forKey: "fallbackOutputUID") }
    }

    // MARK: - 运行时状态
    private var isUsingTargetInput = false
    private var isUsingTargetOutput = false
    private var pendingProgrammaticInputUID: String?
    private var pendingProgrammaticOutputUID: String?
    private var pendingInputSwitchWorkItem: DispatchWorkItem?
    private var pendingOutputSwitchWorkItem: DispatchWorkItem?
    private var pendingRouteStabilizationWorkItem: DispatchWorkItem?
    private var pendingLearnedInputFallbackUID: String?
    private var pendingLearnedOutputFallbackUID: String?

    private let routeStabilizationDelay: TimeInterval = 0.9
    private let bluetoothInputSwitchDelay: TimeInterval = 0.6
    private let bluetoothOutputSwitchDelay: TimeInterval = 1.2
    private let lowFidelityBluetoothOutputSwitchDelay: TimeInterval = 2.0

    // 蓝牙双端点同步锁定相关
    private let bluetoothCoSwitchBaseDelay: TimeInterval = 1.2
    private let bluetoothCoSwitchLowFidelityDelay: TimeInterval = 2.0
    private let bluetoothNegotiationGuardDuration: TimeInterval = 2.5

    private var pendingCoSwitchWorkItem: DispatchWorkItem?
    private var bluetoothNegotiationGuardWorkItem: DispatchWorkItem?
    private var bluetoothNegotiationGuardRouteUID: String?

    @Published private(set) var isLinkedBluetoothLockActive: Bool = false

    init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true

        self.targetInputUID = UserDefaults.standard.string(forKey: "targetInputUID")
        self.targetOutputUID = UserDefaults.standard.string(forKey: "targetOutputUID")

        self.preferredFallbackInputUID = UserDefaults.standard.string(forKey: "preferredFallbackInputUID")
        self.preferredFallbackOutputUID = UserDefaults.standard.string(forKey: "preferredFallbackOutputUID")

        self.learnedFallbackInputUID = UserDefaults.standard.string(forKey: "fallbackInputUID")
        self.learnedFallbackOutputUID = UserDefaults.standard.string(forKey: "fallbackOutputUID")

        setupManagerCallbacks()
        refreshDevicesSnapshot()
        seedLearnedFallbackCandidatesFromCurrentDefaults()

        AudioDeviceManager.shared.startObserving()
        scheduleRouteStabilization(reason: "startup")
    }

    deinit {
        AudioDeviceManager.shared.stopObserving()
    }

    // MARK: - 更新内部缓存
    private func setupManagerCallbacks() {
        AudioDeviceManager.shared.onDeviceListChanged = { [weak self] in
            guard let self = self else { return }
            self.refreshDevicesSnapshot()

            // 协商保护期内,如果目标设备仍在 device list,吸收事件;
            // 如果目标设备消失了(AirPods 拔了),立即结束保护期并评估
            if let route = self.bluetoothNegotiationGuardRouteUID {
                let stillPresent = self.inputs.contains(where: { $0.routeGroupUID == route })
                                && self.outputs.contains(where: { $0.routeGroupUID == route })
                if stillPresent { return }
                self.cancelBluetoothNegotiationGuard()
            }

            self.scheduleRouteStabilization(reason: "device-list")
        }

        AudioDeviceManager.shared.onDefaultInputChanged = { [weak self] newDevice in
            guard let self = self else { return }
            self.currentInput = newDevice
            self.handleInputDeviceChange(newDevice)
        }

        AudioDeviceManager.shared.onDefaultOutputChanged = { [weak self] newDevice in
            guard let self = self else { return }
            self.currentOutput = newDevice
            self.handleOutputDeviceChange(newDevice)
        }
    }

    private func refreshDevicesSnapshot() {
        let all = AudioDeviceManager.shared.getAllDevices()
        inputs = all.filter { $0.isInput }
        outputs = all.filter { $0.isOutput }
        currentInput = AudioDeviceManager.shared.getDefaultInputDevice()
        currentOutput = AudioDeviceManager.shared.getDefaultOutputDevice()
    }

    private func applyRoutingPolicyImmediately() {
        cancelPendingSwitchWorkItems()
        pendingRouteStabilizationWorkItem?.cancel()
        pendingRouteStabilizationWorkItem = nil
        refreshDevicesSnapshot()
        evaluateRoutingPolicy()
    }

    private func scheduleRouteStabilization(reason: String) {
        cancelPendingSwitchWorkItems()
        pendingRouteStabilizationWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRouteStabilizationWorkItem = nil
            self.refreshDevicesSnapshot()
            self.evaluateRoutingPolicy()
            print("【路由稳定】已处理事件: \(reason)")
        }

        pendingRouteStabilizationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + routeStabilizationDelay, execute: workItem)
    }

    private func evaluateRoutingPolicy() {
        commitLearnedFallbackCandidates()

        // 蓝牙双端点锁定:同一路由组用原子切换,绕过分散的 evaluateInput/Output
        if let pair = linkedBluetoothCoSwitchTarget(), isEnabled {
            let inputOk = AudioDeviceManager.shared.inputRoutingMatches(pair.input)
            let outputOk = AudioDeviceManager.shared.outputRoutingMatches(pair.output)
            if inputOk && outputOk {
                isUsingTargetInput = true
                isUsingTargetOutput = true
                isLinkedBluetoothLockActive = true
                return
            }
            learnStableInputFallbackIfNeeded(currentInput)
            learnStableOutputFallbackIfNeeded(currentOutput)
            scheduleLinkedBluetoothCoSwitch(input: pair.input, output: pair.output)
            isUsingTargetInput = true
            isUsingTargetOutput = true
            isLinkedBluetoothLockActive = true
            return
        }

        isLinkedBluetoothLockActive = false
        evaluateInputSwitching()
        evaluateOutputSwitching()
    }

    /// 当且仅当目标输入与目标输出属于同一蓝牙路由组,且都在当前设备列表中,才视为双端点锁定模式
    private func linkedBluetoothCoSwitchTarget() -> (input: AudioDevice, output: AudioDevice)? {
        guard let inUID = targetInputUID, let outUID = targetOutputUID else { return nil }
        guard routeGroupUID(for: inUID) == routeGroupUID(for: outUID) else { return nil }
        guard let input = inputs.first(where: { $0.uid == inUID }),
              let output = outputs.first(where: { $0.uid == outUID }) else { return nil }
        guard input.isBluetoothTransport, output.isBluetoothTransport else { return nil }
        return (input, output)
    }

    private func bluetoothCoSwitchDelay(for output: AudioDevice) -> TimeInterval {
        output.isLowFidelityBluetoothOutput
            ? bluetoothCoSwitchLowFidelityDelay
            : bluetoothCoSwitchBaseDelay
    }

    /// 蓝牙双端点原子切换:消除输入输出延迟错位,先 output 再 input,引导 daemon 一次性选定 HFP
    private func scheduleLinkedBluetoothCoSwitch(input: AudioDevice, output: AudioDevice) {
        cancelPendingSwitchWorkItems()
        pendingCoSwitchWorkItem?.cancel()
        pendingRouteStabilizationWorkItem?.cancel()
        pendingRouteStabilizationWorkItem = nil

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCoSwitchWorkItem = nil
            guard self.isEnabled else { return }
            guard let resolvedOutput = self.outputs.first(where: { $0.uid == output.uid }),
                  let resolvedInput = self.inputs.first(where: { $0.uid == input.uid }) else { return }

            // ① 先 output(指引 daemon 选择 HFP 路由)
            if !AudioDeviceManager.shared.outputRoutingMatches(resolvedOutput) {
                self.pendingProgrammaticOutputUID = resolvedOutput.uid
                AudioDeviceManager.shared.setDefaultOutputDevice(resolvedOutput)
            }
            // ② 再 input(同一 dispatch 内紧接,daemon 一次性决定)
            if !AudioDeviceManager.shared.inputRoutingMatches(resolvedInput) {
                self.pendingProgrammaticInputUID = resolvedInput.uid
                AudioDeviceManager.shared.setDefaultInputDevice(resolvedInput)
            }
            // ③ 进入 HFP 协商保护期
            self.beginBluetoothNegotiationGuard(routeUID: self.routeGroupUID(for: resolvedOutput.uid))
            print("【双端点锁定】已下发同步切换: \(resolvedInput.name) ↔ \(resolvedOutput.name)")
        }

        pendingCoSwitchWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + bluetoothCoSwitchDelay(for: output),
            execute: workItem
        )
    }

    /// 启动 HFP 协商保护期:在保护期内吸收 macOS 协商过程产生的过渡态事件
    private func beginBluetoothNegotiationGuard(routeUID: String) {
        bluetoothNegotiationGuardWorkItem?.cancel()
        bluetoothNegotiationGuardRouteUID = routeUID

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.bluetoothNegotiationGuardWorkItem = nil
            self.bluetoothNegotiationGuardRouteUID = nil
            self.refreshDevicesSnapshot()
            self.evaluateRoutingPolicy()
            print("【双端点锁定】HFP 协商保护期结束,已校准")
        }
        bluetoothNegotiationGuardWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + bluetoothNegotiationGuardDuration,
            execute: workItem
        )
    }

    /// 检查事件应否被保护期吸收。返回 true 表示已吸收,调用方应直接 return
    private func absorbsEventDuringNegotiationGuard(newDeviceUID: String?) -> Bool {
        guard let guardRoute = bluetoothNegotiationGuardRouteUID else { return false }
        // 没有 newDeviceUID 视为"未知/中间态",吸收
        guard let newUID = newDeviceUID else { return true }
        // 仍在目标路由组内 → 是 macOS 内部协商的过渡态,吸收
        if routeGroupUID(for: newUID) == guardRoute {
            return true
        }
        // 用户切到了其他设备:认为意图变更,主动结束保护期,不吸收
        cancelBluetoothNegotiationGuard()
        return false
    }

    private func cancelBluetoothNegotiationGuard() {
        bluetoothNegotiationGuardWorkItem?.cancel()
        bluetoothNegotiationGuardWorkItem = nil
        bluetoothNegotiationGuardRouteUID = nil
    }

    private func seedLearnedFallbackCandidatesFromCurrentDefaults() {
        pendingLearnedInputFallbackUID = fallbackCandidateUID(
            for: currentInput,
            targetUID: targetInputUID,
            preferredFallbackUID: preferredFallbackInputUID
        )
        pendingLearnedOutputFallbackUID = fallbackCandidateUID(
            for: currentOutput,
            targetUID: targetOutputUID,
            preferredFallbackUID: preferredFallbackOutputUID
        )
    }

    private func fallbackCandidateUID(
        for device: AudioDevice?,
        targetUID: String?,
        preferredFallbackUID: String?
    ) -> String? {
        guard let device else { return nil }
        guard device.uid != targetUID else { return nil }
        guard device.uid != preferredFallbackUID else { return nil }
        return device.uid
    }

    private func commitLearnedFallbackCandidates() {
        if let candidateUID = pendingLearnedInputFallbackUID {
            defer { pendingLearnedInputFallbackUID = nil }
            guard pendingProgrammaticInputUID == nil,
                  currentInput?.uid == candidateUID,
                  includesInputDevice(uid: candidateUID),
                  candidateUID != targetInputUID,
                  candidateUID != preferredFallbackInputUID else {
                return
            }
            learnedFallbackInputUID = candidateUID
        }

        if let candidateUID = pendingLearnedOutputFallbackUID {
            defer { pendingLearnedOutputFallbackUID = nil }
            guard pendingProgrammaticOutputUID == nil,
                  currentOutput?.uid == candidateUID,
                  includesOutputDevice(uid: candidateUID),
                  candidateUID != targetOutputUID,
                  candidateUID != preferredFallbackOutputUID else {
                return
            }
            learnedFallbackOutputUID = candidateUID
        }
    }

    // MARK: - 核心策略：检查并进行切换

    private func evaluateInputSwitching() {
        guard isEnabled else {
            isUsingTargetInput = currentInput?.uid == targetInputUID
            return
        }

        if let targetUID = targetInputUID,
           let targetDevice = inputs.first(where: { $0.uid == targetUID }) {
            if currentInput?.uid != targetUID {
                learnStableInputFallbackIfNeeded(currentInput)
                isUsingTargetInput = true
                switchInput(to: targetDevice)
                print("【麦克风】已自动切换到目标: \(targetDevice.name)")
            } else {
                isUsingTargetInput = true
            }
            return
        }

        if shouldHoldFallbackForLinkedPrimary(
            missingTargetUID: targetInputUID,
            siblingTargetUID: targetOutputUID,
            devicesForMissingTarget: inputs,
            siblingDevices: outputs
        ) {
            isUsingTargetInput = false
            return
        }

        isUsingTargetInput = false

        guard let fallbackDevice = resolvedFallbackInputDevice() else { return }

        if currentInput?.uid != fallbackDevice.uid {
            switchInput(to: fallbackDevice)
            if targetInputUID == nil {
                print("【麦克风】未设置目标，使用备选: \(fallbackDevice.name)")
            } else {
                print("【麦克风】目标离线，回退到: \(fallbackDevice.name)")
            }
        }
    }

    private func evaluateOutputSwitching() {
        guard isEnabled else {
            isUsingTargetOutput = currentOutput?.uid == targetOutputUID
            return
        }

        if let targetUID = targetOutputUID,
           let targetDevice = outputs.first(where: { $0.uid == targetUID }) {
            if !AudioDeviceManager.shared.outputRoutingMatches(targetDevice) {
                learnStableOutputFallbackIfNeeded(currentOutput)
                isUsingTargetOutput = true
                switchOutput(to: targetDevice)
                print("【音箱】已自动切换到目标: \(targetDevice.name)")
            } else {
                isUsingTargetOutput = true
            }
            return
        }

        if shouldHoldFallbackForLinkedPrimary(
            missingTargetUID: targetOutputUID,
            siblingTargetUID: targetInputUID,
            devicesForMissingTarget: outputs,
            siblingDevices: inputs
        ) {
            isUsingTargetOutput = false
            return
        }

        isUsingTargetOutput = false

        guard let fallbackDevice = resolvedFallbackOutputDevice() else { return }

        if !AudioDeviceManager.shared.outputRoutingMatches(fallbackDevice) {
            switchOutput(to: fallbackDevice)
            if targetOutputUID == nil {
                print("【音箱】未设置目标，使用备选: \(fallbackDevice.name)")
            } else {
                print("【音箱】目标离线，回退到: \(fallbackDevice.name)")
            }
        }
    }

    private func handleInputDeviceChange(_ newDevice: AudioDevice?) {
        let hadProgrammaticSwitchInFlight = pendingProgrammaticInputUID != nil
        let matchedProgrammaticSwitch = pendingProgrammaticInputUID == newDevice?.uid

        pendingProgrammaticInputUID = nil
        if matchedProgrammaticSwitch {
            pendingLearnedInputFallbackUID = nil
        } else if !hadProgrammaticSwitchInFlight {
            pendingLearnedInputFallbackUID = fallbackCandidateUID(
                for: newDevice,
                targetUID: targetInputUID,
                preferredFallbackUID: preferredFallbackInputUID
            )
        }

        isUsingTargetInput = newDevice?.uid == targetInputUID

        if absorbsEventDuringNegotiationGuard(newDeviceUID: newDevice?.uid) {
            return
        }
        scheduleRouteStabilization(reason: "default-input")
    }

    private func handleOutputDeviceChange(_ newDevice: AudioDevice?) {
        let hadProgrammaticSwitchInFlight = pendingProgrammaticOutputUID != nil
        let matchedProgrammaticSwitch = pendingProgrammaticOutputUID == newDevice?.uid

        pendingProgrammaticOutputUID = nil
        if matchedProgrammaticSwitch {
            pendingLearnedOutputFallbackUID = nil
        } else if !hadProgrammaticSwitchInFlight {
            pendingLearnedOutputFallbackUID = fallbackCandidateUID(
                for: newDevice,
                targetUID: targetOutputUID,
                preferredFallbackUID: preferredFallbackOutputUID
            )
        }

        isUsingTargetOutput = newDevice?.uid == targetOutputUID

        if absorbsEventDuringNegotiationGuard(newDeviceUID: newDevice?.uid) {
            return
        }
        scheduleRouteStabilization(reason: "default-output")
    }

    private func switchInput(to device: AudioDevice) {
        pendingInputSwitchWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingInputSwitchWorkItem = nil
            guard self.isEnabled else { return }
            guard let resolvedDevice = self.inputs.first(where: { $0.uid == device.uid }) else { return }
            guard !AudioDeviceManager.shared.inputRoutingMatches(resolvedDevice) else { return }

            self.pendingProgrammaticInputUID = resolvedDevice.uid
            AudioDeviceManager.shared.setDefaultInputDevice(resolvedDevice)
        }

        pendingInputSwitchWorkItem = workItem

        let delay = device.isBluetoothTransport ? bluetoothInputSwitchDelay : 0
        if delay == 0 {
            workItem.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func switchOutput(to device: AudioDevice) {
        pendingOutputSwitchWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingOutputSwitchWorkItem = nil
            guard self.isEnabled else { return }
            guard let resolvedDevice = self.outputs.first(where: { $0.uid == device.uid }) else { return }
            guard !AudioDeviceManager.shared.outputRoutingMatches(resolvedDevice) else { return }

            self.pendingProgrammaticOutputUID = resolvedDevice.uid
            AudioDeviceManager.shared.setDefaultOutputDevice(resolvedDevice)
        }

        pendingOutputSwitchWorkItem = workItem

        let delay = outputSwitchDelay(for: device)
        if delay == 0 {
            workItem.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func outputSwitchDelay(for device: AudioDevice) -> TimeInterval {
        guard device.isBluetoothTransport else { return 0 }
        return device.isLowFidelityBluetoothOutput ? lowFidelityBluetoothOutputSwitchDelay : bluetoothOutputSwitchDelay
    }

    private func cancelPendingWork() {
        cancelPendingSwitchWorkItems()
        pendingRouteStabilizationWorkItem?.cancel()
        pendingRouteStabilizationWorkItem = nil
        cancelBluetoothNegotiationGuard()
        isLinkedBluetoothLockActive = false
        pendingProgrammaticInputUID = nil
        pendingProgrammaticOutputUID = nil
        pendingLearnedInputFallbackUID = nil
        pendingLearnedOutputFallbackUID = nil
    }

    private func cancelPendingSwitchWorkItems() {
        pendingInputSwitchWorkItem?.cancel()
        pendingOutputSwitchWorkItem?.cancel()
        pendingCoSwitchWorkItem?.cancel()
        pendingInputSwitchWorkItem = nil
        pendingOutputSwitchWorkItem = nil
        pendingCoSwitchWorkItem = nil
    }

    private func resolvedFallbackInputDevice() -> AudioDevice? {
        if let preferredFallbackInputUID,
           preferredFallbackInputUID != targetInputUID,
           let device = inputs.first(where: { $0.uid == preferredFallbackInputUID }) {
            return device
        }

        if let learnedFallbackInputUID,
           learnedFallbackInputUID != targetInputUID,
           let device = inputs.first(where: { $0.uid == learnedFallbackInputUID }) {
            return device
        }

        return nil
    }

    private func resolvedFallbackOutputDevice() -> AudioDevice? {
        if let preferredFallbackOutputUID,
           preferredFallbackOutputUID != targetOutputUID,
           let device = outputs.first(where: { $0.uid == preferredFallbackOutputUID }) {
            return device
        }

        if let learnedFallbackOutputUID,
           learnedFallbackOutputUID != targetOutputUID,
           let device = outputs.first(where: { $0.uid == learnedFallbackOutputUID }) {
            return device
        }

        return nil
    }

    private func learnStableInputFallbackIfNeeded(_ device: AudioDevice?) {
        guard pendingRouteStabilizationWorkItem == nil, pendingProgrammaticInputUID == nil else { return }
        guard let device, device.isInput, device.uid != targetInputUID, device.uid != preferredFallbackInputUID else { return }
        learnedFallbackInputUID = device.uid
    }

    private func learnStableOutputFallbackIfNeeded(_ device: AudioDevice?) {
        guard pendingRouteStabilizationWorkItem == nil, pendingProgrammaticOutputUID == nil else { return }
        guard let device, device.isOutput, device.uid != targetOutputUID, device.uid != preferredFallbackOutputUID else { return }
        learnedFallbackOutputUID = device.uid
    }

    private func shouldHoldFallbackForLinkedPrimary(
        missingTargetUID: String?,
        siblingTargetUID: String?,
        devicesForMissingTarget: [AudioDevice],
        siblingDevices: [AudioDevice]
    ) -> Bool {
        guard let missingTargetUID, let siblingTargetUID else { return false }

        let missingRouteUID = routeGroupUID(for: missingTargetUID)
        guard missingRouteUID == routeGroupUID(for: siblingTargetUID) else { return false }

        let targetEndpointIsAvailable = devicesForMissingTarget.contains(where: { $0.uid == missingTargetUID })
        guard !targetEndpointIsAvailable else { return false }

        return devicesForMissingTarget.contains(where: { $0.routeGroupUID == missingRouteUID })
            || siblingDevices.contains(where: { $0.routeGroupUID == missingRouteUID })
    }

    private func routeGroupUID(for uid: String) -> String {
        uid.replacingOccurrences(of: ":(input|output)$", with: "", options: .regularExpression)
    }

    func includesInputDevice(uid: String?) -> Bool {
        guard let uid else { return false }
        return inputs.contains(where: { $0.uid == uid })
    }

    func includesOutputDevice(uid: String?) -> Bool {
        guard let uid else { return false }
        return outputs.contains(where: { $0.uid == uid })
    }

    var inputStatusUID: String? {
        if let targetInputUID, includesInputDevice(uid: targetInputUID) {
            return targetInputUID
        }

        if let fallbackUID = resolvedFallbackInputDevice()?.uid {
            return fallbackUID
        }

        return targetInputUID ?? preferredFallbackInputUID ?? learnedFallbackInputUID
    }

    var outputStatusUID: String? {
        if let targetOutputUID, includesOutputDevice(uid: targetOutputUID) {
            return targetOutputUID
        }

        if let fallbackUID = resolvedFallbackOutputDevice()?.uid {
            return fallbackUID
        }

        return targetOutputUID ?? preferredFallbackOutputUID ?? learnedFallbackOutputUID
    }
}
