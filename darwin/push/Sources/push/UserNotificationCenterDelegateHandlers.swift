import Foundation
import UserNotifications

#if SWIFT_PACKAGE
    import push_pigeon
#endif

/// Installed on `UNUserNotificationCenter` before app launch finishes. The
/// singleton is shared by the plugin and by apps that call
/// `PushPlugin.setUpUserNotificationCenterDelegate()` in their AppDelegate.
final class UserNotificationCenterDelegateHandlers: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UserNotificationCenterDelegateHandlers()

    private let installLock = NSLock()
    private let apiLock = NSLock()
    private var originalDelegate: UNUserNotificationCenterDelegate?
    private var isInstalled = false
    private var pushFlutterApi: PUPushFlutterApi?

    private override init() {
        super.init()
    }

    /// Safe to call more than once: the first caller wraps the delegate that was
    /// installed at that point; later callers (including plugin registration) reuse it.
    static func install() {
        shared.install()
    }

    /// The Flutter API is only available after plugin registration, which happens
    /// after app launch when the app uses the UIScene lifecycle.
    func setPushFlutterApi(_ api: PUPushFlutterApi) {
        apiLock.lock()
        pushFlutterApi = api
        apiLock.unlock()
    }

    private var flutterApi: PUPushFlutterApi? {
        apiLock.lock()
        defer { apiLock.unlock() }
        return pushFlutterApi
    }

    private func install() {
        installLock.lock()
        defer { installLock.unlock() }
        guard !isInstalled else { return }

        let center = UNUserNotificationCenter.current()
        if let current = center.delegate as? NSObject, current === self {
            isInstalled = true
            return
        }
        originalDelegate = center.delegate
        center.delegate = self
        isInstalled = true
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // When a foreground notification is delivered and the user schedules a local notification, this is called twice.
        // - First, when the notification is received from APNs directly. To be consistent with Android behaviour, we ignore it. In this case, notification.request.trigger is a `UNPushNotificationTrigger`
        // - When received from flutter_local_notifications, I want to display it. In this case, notification.request.trigger is nil.
        guard notification.request.trigger is UNPushNotificationTrigger else {
            let presentationOptions = getPresentationOptionsFromUserInfo(
                notification.request.content.userInfo
            )
            completionHandler(presentationOptions)
            return
        }

        guard let flutterApi else {
            // The engine is not ready yet, so there is nobody to forward this to.
            completionHandler([])
            return
        }
        let message = PURemoteMessage.from(userInfo: notification.request.content.userInfo)
        flutterApi.onMessageMessage(message) { _ in }
        // Do not display the notification received from APNs
        completionHandler([])
    }

    private var userTappedOnNotificationCount = 0

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Prevents sending notification to users twice when their app is launched by a tap.
        // We will send that one when the user requests for the "Push.instance.notificationTapWhichLaunchedAppFromTerminated" (Dart code)
        let skip = userTappedOnNotificationCount == 0
            && PushHostHandlers.notificationTapWhichLaunchedAppUserInfo != nil
        if !skip, let flutterApi {
            let userInfo = response.notification.request.content.userInfo as? [String: Any] ?? [:]
            flutterApi.onNotificationTapMessage(userInfo) { _ in }
        }

        userTappedOnNotificationCount += 1
        callOriginalDidReceiveDelegateMethod(
            center: center,
            response: response,
            completionHandler: completionHandler
        )
    }

    // Allow users original UNUserNotificationCenterDelegate they set to respond.
    private func callOriginalDidReceiveDelegateMethod(
        center: UNUserNotificationCenter,
        response: UNNotificationResponse,
        completionHandler: @escaping () -> Void
    ) {
        // `as` is used because userNotificationCenter on its own is ambiguous (userNotificationCenter corresponds to 3 methods).
        // See https://stackoverflow.com/questions/35658334/how-do-i-resolve-ambiguous-use-of-compile-error-with-swift-selector-syntax
        let didReceiveDelegateMethodSelector = #selector(
            userNotificationCenter as (UNUserNotificationCenter, UNNotificationResponse, @escaping () -> Void) -> Void
        )
        if let originalDelegate, originalDelegate.responds(to: didReceiveDelegateMethodSelector) {
            originalDelegate.userNotificationCenter?(
                center, didReceive: response, withCompletionHandler: completionHandler
            )
        } else {
            completionHandler()
        }
    }

    @available(iOS 12.0, *)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        flutterApi?.onOpenNotificationSettings { _ in }
        callOriginalOpenSettingsForDelegateMethod(center: center, notification: notification)
    }

    @available(iOS 12.0, *)
    private func callOriginalOpenSettingsForDelegateMethod(
        center: UNUserNotificationCenter,
        notification: UNNotification?
    ) {
        let openSettingsForDelegateMethodSelector = #selector(
            userNotificationCenter as (UNUserNotificationCenter, UNNotification?) -> Void
        )
        if let originalDelegate,
           originalDelegate.responds(to: openSettingsForDelegateMethodSelector) {
            originalDelegate.userNotificationCenter?(center, openSettingsFor: notification)
        }
    }

    // Parses userInfo to get presentation options. If some present value is not found, it is  considered as true
    private func getPresentationOptionsFromUserInfo(
        _ userInfo: [AnyHashable: Any]
    ) -> UNNotificationPresentationOptions {
        let presentBanner = (userInfo["presentBanner"] as? Bool) ?? true
        let presentAlert = (userInfo["presentAlert"] as? Bool) ?? true
        let presentSound = (userInfo["presentSound"] as? Bool) ?? true
        let presentBadge = (userInfo["presentBadge"] as? Bool) ?? true
        let presentList = (userInfo["presentList"] as? Bool) ?? true

        let presentNotification = presentBanner || presentAlert
        var presentationOptions: UNNotificationPresentationOptions = []

        if presentNotification {
            if #available(iOS 14.0, macOS 11.0, *) {
                presentationOptions.insert(.banner)
            } else {
                presentationOptions.insert(.alert)
            }
        }

        if presentSound {
            presentationOptions.insert(.sound)
        }

        if presentBadge {
            presentationOptions.insert(.badge)
        }

        if presentList {
            if #available(iOS 14.0, macOS 11.0, *) {
                presentationOptions.insert(.list)
            }
        }

        return presentationOptions
    }
}
