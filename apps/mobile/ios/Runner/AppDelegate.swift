import Flutter
import Darwin
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let deviceChannel = FlutterMethodChannel(
      name: "mobile_codex/device",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    deviceChannel.setMethodCallHandler { call, result in
      guard call.method == "model" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let model = UIDevice.current.model.trimmingCharacters(in: .whitespacesAndNewlines)
      let identifier = Self.hardwareIdentifier()
      let system = UIDevice.current.systemVersion.trimmingCharacters(in: .whitespacesAndNewlines)
      let hardware = [name, model, identifier].filter { !$0.isEmpty }.joined(separator: " · ")
      result("\(hardware) (iOS \(system))")
    }
  }

  private static func hardwareIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineSize = MemoryLayout.size(ofValue: systemInfo.machine)
    return withUnsafePointer(to: &systemInfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: machineSize) {
        String(cString: $0)
      }
    }
  }
}
