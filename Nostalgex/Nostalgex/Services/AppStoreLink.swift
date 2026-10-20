import Foundation

/// Apple TV App Store URLs for Nostalgex (tvOS supports star ratings only — no written reviews).
enum AppStoreLink {
    static let appID = "6762563534"

    /// Opens the Nostalgex product page in the tvOS App Store. `itms-apps`, not `https`:
    /// tvOS has no browser, and an https link opened from the app brought up the App Store
    /// without the page. The scheme hands the address straight to the App Store.
    static var productPage: URL {
        URL(string: "itms-apps://apps.apple.com/app/id\(appID)")!
    }
}
