import Foundation

/// Passed only by the keyboard UI test. A normal launch never includes this argument.
enum UITestLaunch {
    static let argument = "-TruckoRigUITest"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }
}
