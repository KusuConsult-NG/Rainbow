import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // The Bluetooth mesh radio (MeshBleRadio.swift). Held for the life of the app:
  // its channels stop answering the moment it is released.
  private var meshRadio: MeshBleRadio?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "MeshBleRadio") {
      meshRadio = MeshBleRadio(messenger: registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
