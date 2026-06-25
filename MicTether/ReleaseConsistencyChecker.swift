import Foundation

enum ReleaseConsistencyChecker {
    private static let expectedBundleIdentifier = "com.zimin.MicTether"

    static func logIfNeeded(bundle: Bundle = .main) {
        let actualBundleIdentifier = bundle.bundleIdentifier ?? "<missing>"
        guard actualBundleIdentifier != expectedBundleIdentifier else { return }

        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        print(
            "【ReleaseCheck】当前运行包为 \(actualBundleIdentifier) v\(version) (\(build))，" +
            "与源码期望的 \(expectedBundleIdentifier) 不一致。请确认 /Applications 中的安装包是否来自当前源码。"
        )
    }
}
