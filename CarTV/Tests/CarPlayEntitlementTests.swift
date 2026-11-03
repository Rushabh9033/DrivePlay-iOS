import XCTest
import Foundation
@testable import CarTV

/// The CarPlay entitlements are Apple-granted — they live on the app id — so the
/// build asks for exactly what the app id carries and the device build either
/// signs or does not.
///
/// DrivePlay keeps one file per category and picks the one it builds with:
/// `CARPLAY_CATEGORY` selects the file *and* tells the app what it got, so the
/// two can never disagree. The video build asks for the audio key as well: the
/// app's profile carries both, and an app that has both appears on every car.
///
/// The helper script is part of the repo, so it has to work on any machine: the
/// entitlement comes from the entitlements files (not a copy in the script), and
/// the device is detected at run time. The iOS test bundle cannot spawn
/// processes, so the contract is checked statically here.
final class CarPlayEntitlementTests: XCTestCase {

    private var repositoryRoot: URL {
        RepositoryFixture.root
    }

    private func entitlementsURL(_ category: String) -> URL {
        repositoryRoot.appendingPathComponent("CarTV/Resources/CarTV.\(category).entitlements")
    }

    private var scriptURL: URL {
        repositoryRoot.appendingPathComponent("scripts/carplay_grant.sh")
    }

    private func carPlayCategories(in url: URL) throws -> Set<String> {
        let text = try String(contentsOf: url, encoding: .utf8)
        return Set(text.components(separatedBy: "<key>").compactMap { part -> String? in
            guard let key = part.components(separatedBy: "</key>").first else { return nil }
            let name = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.hasPrefix("com.apple.developer.carplay-") ? name : nil
        })
    }

    /// AC27: the entitlements file asks for exactly what the app id carries.
    ///
    /// The audio build asks for the audio key only — it is the fallback that has
    /// to sign with the old audio profile. The video build asks for **both**:
    /// Apple's profile for this app id carries both keys, and Apple's own
    /// guidance ("Rev up your CarPlay app", WWDC26) is to include both when the
    /// content suits both, so the app appears on every car and the picture
    /// appears on the cars that support "video in car".
    func test_AC27_the_entitlements_files_ask_for_exactly_what_the_app_id_carries() throws {
        try RepositoryFixture.skipUnlessPresent()
        XCTAssertEqual(try carPlayCategories(in: entitlementsURL("audio")), ["com.apple.developer.carplay-audio"])
        XCTAssertEqual(try carPlayCategories(in: entitlementsURL("video")),
                       ["com.apple.developer.carplay-audio", "com.apple.developer.carplay-video"])
    }

    /// AC35: the build picks the entitlements file and tells the app the category
    /// from the **same** setting, so the app can never ask CarPlay for a video
    /// surface it is not entitled to.
    func test_AC35_the_build_and_the_app_agree_on_the_carplay_category() throws {
        try RepositoryFixture.skipUnlessPresent()
        let text = try String(contentsOf: repositoryRoot.appendingPathComponent("project.yml"), encoding: .utf8)

        XCTAssertTrue(text.contains("CODE_SIGN_ENTITLEMENTS: CarTV/Resources/CarTV.$(CARPLAY_CATEGORY).entitlements"),
                      "the entitlements file has to follow the category")
        XCTAssertTrue(text.contains("CarPlayCategory: $(CARPLAY_CATEGORY)"),
                      "the app has to be told the category it was signed with")
    }

    /// AC28: the helper asks for the entitlement the app asks for (it reads the
    /// entitlements files instead of carrying its own copy), detects the device at
    /// run time and tells the developer what to do when the phone is missing.
    func test_AC28_the_grant_helper_follows_the_entitlements_file_and_finds_the_device() throws {
        try RepositoryFixture.skipUnlessPresent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path))
        let text = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(text.contains("CarTV/Resources/CarTV.${CARPLAY_CATEGORY}.entitlements"),
                      "the entitlement has to come from the entitlements file")
        XCTAssertTrue(text.contains("-showdestinations"),
                      "the device has to be detected at run time")
        XCTAssertFalse(text.contains("/Users/"),
                       "the script must not depend on one machine's home directory")
        XCTAssertTrue(text.contains("-allowProvisioningUpdates"),
                      "the new profile is fetched by Xcode's automatic signing")
        XCTAssertTrue(text.contains("no connected iPhone found"),
                      "a missing phone has to end in a clear error")
    }
}
