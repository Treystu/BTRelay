import UIKit
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  let pm = PeripheralManager()
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds)
    let vc = SettingsViewController()
    window?.rootViewController = UINavigationController(rootViewController: vc)
    window?.makeKeyAndVisible()
    pm.start()
    return true
  }
}
