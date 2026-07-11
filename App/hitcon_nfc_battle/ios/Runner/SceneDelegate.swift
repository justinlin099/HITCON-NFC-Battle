import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    for userActivity in connectionOptions.userActivities {
      IosNfcLaunchEvidenceStore.shared.capture(userActivity)
    }
    super.scene(
      scene,
      willConnectTo: session,
      options: connectionOptions
    )
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    IosNfcLaunchEvidenceStore.shared.capture(userActivity)
    super.scene(scene, continue: userActivity)
  }
}
