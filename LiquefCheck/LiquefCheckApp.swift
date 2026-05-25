import SwiftUI
import GoogleMobileAds
import AppTrackingTransparency

@main
struct LiquefCheckApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        ATTrackingManager.requestTrackingAuthorization { _ in
                            DispatchQueue.main.async {
                                GADMobileAds.sharedInstance().start(completionHandler: nil)
                            }
                        }
                    }
                }
        }
    }
}
