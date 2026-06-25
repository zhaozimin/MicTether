import Foundation
import CoreAudio

/// 表示一个音频设备的模型
struct AudioDevice: Identifiable, Equatable {
    var id: AudioObjectID
    var name: String
    var uid: String
    var isInput: Bool
    var isOutput: Bool
    var inputChannelCount: Int
    var outputChannelCount: Int
    var nominalSampleRate: Double
    var transportType: UInt32
    var canBeDefaultSystemOutput: Bool

    var isBluetoothTransport: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    var isLowFidelityBluetoothOutput: Bool {
        isBluetoothTransport && isOutput && outputChannelCount <= 1 && nominalSampleRate > 0 && nominalSampleRate <= 24_000
    }

    var routeGroupUID: String {
        uid.replacingOccurrences(of: ":(input|output)$", with: "", options: .regularExpression)
    }
}

/// 管理和操作 macOS 音频设备的单例类
class AudioDeviceManager {
    static let shared = AudioDeviceManager()
    
    private init() {}
    
    /// 当设备列表发生变化时的回调
    var onDeviceListChanged: (() -> Void)?
    
    /// 当系统默认输入设备变化时的回调
    var onDefaultInputChanged: ((AudioDevice?) -> Void)?
    
    /// 当系统默认输出设备变化时的回调
    var onDefaultOutputChanged: ((AudioDevice?) -> Void)?

    // MARK: - 查询设备列表

    /// 获取系统中所有的音频设备
    func getAllDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return [] }
        
        return deviceIDs.compactMap { getDevice(by: $0) }
    }
    
    /// 根据 ID 获取具体的设备信息
    private func getDevice(by objectID: AudioObjectID) -> AudioDevice? {
        guard let name = getStringProperty(for: objectID, selector: kAudioDevicePropertyDeviceNameCFString),
              let uid = getStringProperty(for: objectID, selector: kAudioDevicePropertyDeviceUID) else {
            return nil
        }
        
        let inputChannelCount = getChannelCount(for: objectID, scope: kAudioDevicePropertyScopeInput)
        let outputChannelCount = getChannelCount(for: objectID, scope: kAudioDevicePropertyScopeOutput)
        let isInput = inputChannelCount > 0
        let isOutput = outputChannelCount > 0
        
        // 过滤掉既没有输入也没有输出的设备
        if !isInput && !isOutput { return nil }
        
        let nominalSampleRate = getDoubleProperty(for: objectID, selector: kAudioDevicePropertyNominalSampleRate) ?? 0
        let transportType = getUInt32Property(for: objectID, selector: kAudioDevicePropertyTransportType) ?? kAudioDeviceTransportTypeUnknown
        let canBeDefaultSystemOutput = (getUInt32Property(
            for: objectID,
            selector: kAudioDevicePropertyDeviceCanBeDefaultSystemDevice,
            scope: kAudioDevicePropertyScopeOutput
        ) ?? 0) != 0
        
        return AudioDevice(
            id: objectID,
            name: name,
            uid: uid,
            isInput: isInput,
            isOutput: isOutput,
            inputChannelCount: inputChannelCount,
            outputChannelCount: outputChannelCount,
            nominalSampleRate: nominalSampleRate,
            transportType: transportType,
            canBeDefaultSystemOutput: canBeDefaultSystemOutput
        )
    }

    /// 获取指定设备的字符串属性
    private func getStringProperty(for objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertyValue: CFString? = nil
        var propertySize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &propertyValue) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &propertySize, pointer)
        }
        guard status == noErr else { return nil }
        return propertyValue as String?
    }

    private func getUInt32Property(
        for objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &propertySize, &value)
        guard status == noErr else { return nil }
        return value
    }

    private func getDoubleProperty(for objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Double = 0
        var propertySize = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &propertySize, &value)
        guard status == noErr else { return nil }
        return value
    }
    
    /// 检查指定设备在特定作用域（输入或输出）是否有通道
    private func getChannelCount(for objectID: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }
        
        let bufferListPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(dataSize))
        defer { bufferListPointer.deallocate() }
        
        let status2 = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, bufferListPointer)
        guard status2 == noErr else { return 0 }
        
        let bufferList = bufferListPointer.withMemoryRebound(to: AudioBufferList.self, capacity: 1) { pointer in
            UnsafeMutableAudioBufferListPointer(pointer)
        }

        return bufferList.reduce(0) { partialResult, buffer in
            partialResult + Int(buffer.mNumberChannels)
        }
    }

    // MARK: - 默认设备操作
    
    /// 获取当前系统默认输入设备
    func getDefaultInputDevice() -> AudioDevice? {
        getDefaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
    }
    
    /// 获取当前系统默认输出设备
    func getDefaultOutputDevice() -> AudioDevice? {
        getDefaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    /// 获取当前系统默认系统输出设备
    func getDefaultSystemOutputDevice() -> AudioDevice? {
        getDefaultDevice(selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }
    
    private func getDefaultDevice(selector: AudioObjectPropertySelector) -> AudioDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        
        return getDevice(by: deviceID)
    }
    
    /// 设置当前系统默认输入设备
    func setDefaultInputDevice(_ device: AudioDevice) {
        guard getDefaultInputDevice()?.uid != device.uid else { return }
        let status = setDefaultDevice(id: device.id, selector: kAudioHardwarePropertyDefaultInputDevice)
        if status != noErr {
            print("设置默认输入设备失败: \(device.name), status=\(status)")
        }
    }

    func inputRoutingMatches(_ device: AudioDevice) -> Bool {
        getDefaultInputDevice()?.uid == device.uid
    }
    
    /// 设置当前系统默认输出设备
    func setDefaultOutputDevice(_ device: AudioDevice) {
        if getDefaultOutputDevice()?.uid != device.uid {
            let outputStatus = setDefaultDevice(id: device.id, selector: kAudioHardwarePropertyDefaultOutputDevice)
            if outputStatus != noErr {
                print("设置默认输出设备失败: \(device.name), status=\(outputStatus)")
            }
        }

        guard device.canBeDefaultSystemOutput else { return }

        if getDefaultSystemOutputDevice()?.uid != device.uid {
            let systemStatus = setDefaultDevice(id: device.id, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
            if systemStatus != noErr {
                print("设置系统输出设备失败: \(device.name), status=\(systemStatus)")
            }
        }
    }

    func outputRoutingMatches(_ device: AudioDevice) -> Bool {
        guard getDefaultOutputDevice()?.uid == device.uid else { return false }
        guard device.canBeDefaultSystemOutput else { return true }
        return getDefaultSystemOutputDevice()?.uid == device.uid
    }
    
    @discardableResult
    private func setDefaultDevice(id: AudioObjectID, selector: AudioObjectPropertySelector) -> OSStatus {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = id
        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, dataSize, &deviceID)
    }
    
    // MARK: - 监听设备变化
    
    /// 启动事件监听（设备列表更新、默认设备切换）
    func startObserving() {
        // 监听设备列表变化（插拔）
        var deviceListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &deviceListAddress, hardwareListener, nil)
        
        // 监听默认输入设备切换
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, hardwareListener, nil)
        
        // 监听默认输出设备切换
        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, hardwareListener, nil)
    }
    
    /// 停止事件监听
    func stopObserving() {
        var deviceListAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &deviceListAddress, hardwareListener, nil)
        
        var defaultInputAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, hardwareListener, nil)
        
        var defaultOutputAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, hardwareListener, nil)
    }
}

// C 回调函数必须是全局的或是闭包块。此处用全局函数进行路由
private func hardwareListener(inObjectID: AudioObjectID,
                              inNumberAddresses: UInt32,
                              inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
                              inClientData: UnsafeMutableRawPointer?) -> OSStatus {
    
    // 我们需要在主线程中派发通知或者回调
    let addresses = UnsafeBufferPointer(start: inAddresses, count: Int(inNumberAddresses))
    
    for address in addresses {
        switch address.mSelector {
        case kAudioHardwarePropertyDevices:
            DispatchQueue.main.async {
                AudioDeviceManager.shared.onDeviceListChanged?()
            }
        case kAudioHardwarePropertyDefaultInputDevice:
            let device = AudioDeviceManager.shared.getDefaultInputDevice()
            DispatchQueue.main.async {
                AudioDeviceManager.shared.onDefaultInputChanged?(device)
            }
        case kAudioHardwarePropertyDefaultOutputDevice:
            let device = AudioDeviceManager.shared.getDefaultOutputDevice()
            DispatchQueue.main.async {
                AudioDeviceManager.shared.onDefaultOutputChanged?(device)
            }
        default:
            break
        }
    }
    return noErr
}
