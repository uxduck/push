# Updating push versions

This is a reference guide to updating your application through breaking changes in the push package.

## Breaking changes in v3.4

### UIScene lifecycle (iOS)

Apps that adopt UIScene must install the notification center delegate themselves in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`, before that method returns. Flutter registers plugins after app launch under UIScene, which is too late for Apple's `UNUserNotificationCenterDelegate` requirement.

```swift
import Flutter
import push
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        PushPlugin.setUpUserNotificationCenterDelegate()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Forward the APNs token as early as possible; the plugin may not be
    // registered yet when iOS delivers it.
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
```

Apps that have not migrated to UIScene do not need an AppDelegate change. On macOS, replace references to `SwiftPushPlugin.instance` with `PushPlugin.shared`.

### Requirements

SwiftPM support and the scene lifecycle APIs require Flutter 3.41, Dart 3.11, iOS 13 and macOS 10.15.

## Breaking changes in v3.0

Similar to breaking changes in v2, listening to new tokens uses a callback based API. This removes the usage of streams completely from the API, opting for a simpler, callback API.

### Previously
```dart
final onNewTokenSubscription = Push.instance.onNewToken.listen((token) {
print("Just got a new token: $token");
});
final onNotificationTapSubscription =
    Push.instance.onNotificationTap.listen((data) {
print('Notification was tapped:\n'
    'Data: $data \n');
tappedNotificationPayloads.value += [data];
});
// Unsubscribe with:
onNewTokenSubscription.cancel();
onNotificationTapSubscription.cancel();
```

### Now
```dart
final unsubscribeOnNewToken = Push.instance.addOnNewToken((token) {
    print("Just got a new token: $token");
});
final onNotificationTapSubscription =
    Push.instance.addOnNotificationTap((data) {
        print('Notification was tapped:\n'
            'Data: $data \n');
        tappedNotificationPayloads.value += [data];
});
// Unsubscribe with:
unsubscribeOnNewToken();
unsubscribeOnNotificationTap();
```

## Breaking changes in v2


There were breaking changes introduced in v2. See how to migrate from v1.

## Callback API

The stream API has been replaced with a Callback API.

### Previously
```dart
Push.instance.onMessage.listen((message) { /* do something with message */ });
Push.instance.onBackgroundMessage.listen((message) { /* do something with message */ });
```

### Now
```dart
final unsubscribeOnMessage = Push.instance.addOnMessage((message) { /* do something with message */ });
final unsubscribeOnBackgroundMessage = Push.instance.addOnBackgroundMessage((message) { /* do something with message */ });

// Unsubscribe when it makes sense
unsubscribeOnMessage();
unsubscribeOnBackgroundMessage();
```