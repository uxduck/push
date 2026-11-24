import Foundation
import UserNotifications

#if os(iOS)
    import Flutter
    import UIKit

    public typealias DarwinApplication = UIApplication
#elseif os(macOS)
    import FlutterMacOS

    public typealias DarwinApplication = NSApplication
#endif

#if SWIFT_PACKAGE
    import push_pigeon
#endif

/// `@objc(PushPlugin)` pins the Objective-C runtime name, so the
/// `GeneratedPluginRegistrant.m` that Flutter emits for iOS resolves
/// `[PushPlugin registerWithRegistrar:]` without the module prefix. macOS
/// emits a Swift registrant and resolves the class directly.
@objc(PushPlugin)
public class PushPlugin: NSObject, FlutterPlugin {
    /// Available before plugin registration so apps can install the
    /// `UNUserNotificationCenterDelegate` in `application:didFinishLaunchingWithOptions:`.
    public static let shared = PushPlugin()

    private var pushHostHandlers: PushHostHandlers?
    private var pendingDeviceToken: Data?
    private var didRegisterForRemoteNotifications = false

    private override init() {
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        shared.register(with: registrar)
    }

    private func register(with registrar: FlutterPluginRegistrar) {
        #if os(iOS)
            let messenger = registrar.messenger()
        #elseif os(macOS)
            let messenger = registrar.messenger
        #endif

        let handlers = PushHostHandlers(binaryMessenger: messenger)
        pushHostHandlers = handlers

        // Under UIScene, plugins are registered after `didFinishLaunching` returns.
        // APNs can deliver the device token before that, so replay any token the
        // app forwarded to `PushPlugin.shared` manually.
        if let pendingDeviceToken {
            self.pendingDeviceToken = nil
            handlers.application(
                DarwinApplication.shared,
                didRegisterForRemoteNotificationsWithDeviceToken: pendingDeviceToken
            )
        }

        registrar.addApplicationDelegate(self)
        #if os(iOS)
            registrar.addSceneDelegate(self)
        #endif
    }

    /// Must be called from the app delegate's `application:didFinishLaunchingWithOptions:`
    /// before that method returns. Apple requires the notification center delegate to
    /// be installed before app launch completes, but Flutter defers plugin registration
    /// until after launch when the app adopts the UIScene lifecycle.
    ///
    /// This is safe to call more than once. The existing delegate is preserved and
    /// its callbacks are forwarded.
    @objc public static func setUpUserNotificationCenterDelegate() {
        UserNotificationCenterDelegateHandlers.install()
    }

    public func application(
        _ application: DarwinApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        if let pushHostHandlers {
            pushHostHandlers.application(
                application,
                didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
            )
        } else {
            pendingDeviceToken = deviceToken
        }
    }

    public func application(
        _ application: DarwinApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        guard let pushHostHandlers else {
            print("Failed to register device for remote notifications. Error: \(error)")
            return
        }
        pushHostHandlers.application(
            application,
            didFailToRegisterForRemoteNotificationsWithError: error
        )
    }

    /// Registration only needs to happen once, whether it is triggered by the
    /// AppDelegate or by the scene connection callback.
    private func registerForRemoteNotificationsIfNeeded() {
        guard !didRegisterForRemoteNotifications else { return }
        didRegisterForRemoteNotifications = true
        DarwinApplication.shared.registerForRemoteNotifications()
    }

    /// Under UIScene, `launchOptions` is nil and the notification response is
    /// delivered with the scene connection options instead. Keep both paths so
    /// an early AppDelegate callback cannot discard the notification tap.
    private func recordLaunchNotification(_ userInfo: [AnyHashable: Any]?) {
        guard let userInfo else { return }
        PushHostHandlers.notificationTapWhichLaunchedAppUserInfo = userInfo
    }

    #if os(iOS)
        public func application(
            _: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any]
        ) -> Bool {
            let userInfo = launchOptions[UIApplication.LaunchOptionsKey.remoteNotification]
                as? [AnyHashable: Any]
            recordLaunchNotification(userInfo)
            registerForRemoteNotificationsIfNeeded()
            return true
        }

        public func application(
            _ application: UIApplication,
            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
        ) -> Bool {
            pushHostHandlers?.didReceiveRemoteNotification(
                application,
                didReceiveRemoteNotification: userInfo,
                fetchCompletionHandler: completionHandler
            ) ?? false
        }
    #elseif os(macOS)
        // Notification forwarded from NSApplicationDelegate. See https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdidfinishlaunching(_:)
        public func handleDidFinishLaunching(_ notification: Notification) {
            // launchUserNotificationUserInfoKey is: "A key that indicates your app was launched because a user activated a notification in the Notification Center."
            // See https://developer.apple.com/documentation/usernotifications/unnotificationresponse and https://developer.apple.com/documentation/appkit/nsapplication/launchusernotificationuserinfokey
            let response = notification.userInfo?[NSApplication.launchUserNotificationUserInfoKey]
                as? UNNotificationResponse
            recordLaunchNotification(response?.toMap())
            registerForRemoteNotificationsIfNeeded()
        }

        public func application(
            _ application: NSApplication,
            didReceiveRemoteNotification userInfo: [AnyHashable: Any]
        ) {
            pushHostHandlers?.didReceiveRemoteNotification(
                application,
                didReceiveRemoteNotification: userInfo
            )
        }
    #endif

    /// Source compatibility with the pre-3.4.0 singleton name.
    @available(*, deprecated, renamed: "PushPlugin.shared")
    public static var instance: PushPlugin? { shared }
}

/// Source compatibility with code referencing the pre-3.4.0 class name.
@available(*, deprecated, renamed: "PushPlugin")
public typealias SwiftPushPlugin = PushPlugin

#if os(iOS)
    extension PushPlugin: FlutterSceneLifeCycleDelegate {
        /// UIScene replaces `application:didFinishLaunchingWithOptions:` launch options with
        /// `connectionOptions`, so the initial notification tap must be read here too.
        public func scene(
            _: UIScene,
            willConnectTo _: UISceneSession,
            options connectionOptions: UIScene.ConnectionOptions?
        ) -> Bool {
            let response = connectionOptions?.notificationResponse
            recordLaunchNotification(response?.notification.request.content.userInfo)
            registerForRemoteNotificationsIfNeeded()
            // This plugin does not exclusively handle the scene connection; let other
            // plugins receive the connection options as well.
            return false
        }
    }
#endif
