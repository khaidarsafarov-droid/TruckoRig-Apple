import Foundation

/// Passed only by the keyboard UI test. A normal launch never includes this argument.
enum UITestLaunch {
    static let argument = "-TruckoRigUITest"
    static let environmentKey = "TRUCKORIG_UI_TEST"

    static var isEnabled: Bool {
        isEnabled(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func isEnabled(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains(argument) || environment[environmentKey] == "1"
    }

    /// The unit-test host boots the real app, and that launch was raising the notification
    /// alert over the later UI test. Skip the system prompt there and during the UI test.
    static var suppressesSystemPrompts: Bool {
        suppressesSystemPrompts(
            uiTest: isEnabled,
            xcTestConfigurationPath: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]
        )
    }

    static func suppressesSystemPrompts(uiTest: Bool, xcTestConfigurationPath: String?) -> Bool {
        uiTest || (xcTestConfigurationPath?.isEmpty == false)
    }
}
