import Flutter
import UIKit
import push

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Apple requires this before didFinishLaunching returns. Flutter registers
        // plugins later when the app uses the UIScene lifecycle.
        PushPlugin.setUpUserNotificationCenterDelegate()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // APNs can deliver a token before plugin registration. PushPlugin.shared
    // keeps it until the plugin is ready.
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushPlugin.shared.application(
            application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
        )
        super.application(
            application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
        )
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    }
}
