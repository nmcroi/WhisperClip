import Foundation
import XCTest
// @testable, want `cloudKitEntitlementProblem` is intern: hij hoort bij de
// diagnose van de engine en niet bij het publieke oppervlak.
@testable import WhisperShared
@testable import WhisperClipboard

/// Bewaakt de entitlements-bestanden van de Mac-app. Deze tests raken geen
/// netwerk en geen iCloud-account: ze lezen de plists uit de bronboom en
/// vergelijken ze met de constanten in de code.
///
/// Waarom deze tests bestaan (14 augustus 2026): de Mac-app droeg het
/// CloudKit-recht maandenlang niet, omdat het project naar de minimale
/// entitlements wees en de iCloud-variant nergens werd gebruikt. De sync-engine
/// bleef daardoor stil slapend terwijl er honderden wijzigingen in het uitgaande
/// journaal opliepen. Niets in de suite merkte dat op. Dat is precies het gat
/// dat hieronder wordt gedicht.
/// `@MainActor` omdat `HistorySyncEngine` dat is: de container-constante en de
/// diagnosefunctie erven die isolatie, net als in `HistorySyncTests`.
@MainActor
final class EntitlementsTests: XCTestCase {

    /// De map `v2/WhisperClipboard/` in de bronboom, gevonden vanaf dit bestand
    /// (`v2/WhisperClipboardTests/EntitlementsTests.swift`) in plaats van vanuit
    /// de testbundel, want de plists worden niet meegebundeld.
    private var appSourceDirectory: URL {
        URL(fileURLWithPath: #filePath)      // .../v2/WhisperClipboardTests/EntitlementsTests.swift
            .deletingLastPathComponent()     // .../v2/WhisperClipboardTests
            .deletingLastPathComponent()     // .../v2
            .appendingPathComponent("WhisperClipboard")
    }

    private func entitlements(_ name: String) throws -> [String: Any] {
        let url = appSourceDirectory.appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any], "\(name) is geen dictionary")
    }

    private static let containerKey = "com.apple.developer.icloud-container-identifiers"
    private static let environmentKey = "com.apple.developer.icloud-container-environment"

    // MARK: - De iCloud-varianten noemen dezelfde container als de code

    /// Dit is de test die het echte falen van vandaag zou hebben gevangen: een
    /// verschil tussen wat er in de plist staat en wat de engine verwacht. Wijkt
    /// er één teken af, dan slaagt de entitlement-check nooit en blijft de sync
    /// stil slapend.
    func testICloudEntitlementsNoemenDezelfdeContainerAlsDeCode() throws {
        for bestand in ["WhisperClipboard-iCloud.entitlements",
                        "WhisperClipboard-iCloud-Development.entitlements"] {
            let plist = try entitlements(bestand)
            let containers = try XCTUnwrap(
                plist[Self.containerKey] as? [String],
                "\(bestand) mist \(Self.containerKey)"
            )
            XCTAssertEqual(
                containers, [HistorySyncEngine.containerIdentifier],
                "\(bestand) tekent voor een andere container dan de engine verwacht"
            )
        }
    }

    // MARK: - De Debug-variant kan Production niet aanraken

    /// De harde randvoorwaarde: het CloudKit-schema is nog niet naar Production
    /// uitgerold, en dat besluit ligt bij Niels. Het Mac Development-profiel
    /// staat beide omgevingen toe, dus zonder deze sleutel is de omgeving
    /// impliciet. Deze test bewaakt dat niemand hem er stilletjes uit haalt.
    func testDebugVariantPintDeOmgevingOpDevelopment() throws {
        let plist = try entitlements("WhisperClipboard-iCloud-Development.entitlements")
        XCTAssertEqual(
            plist[Self.environmentKey] as? String, "Development",
            "de Debug-variant moet de CloudKit-omgeving hard op Development pinnen"
        )
    }

    // MARK: - De standaardentitlements blijven minimaal

    /// De andere kant van dezelfde medaille. `com.apple.developer.*` zijn
    /// restricted entitlements: een ad-hoc handtekening draagt ze wel, maar het
    /// systeem honoreert ze niet. `hasCloudKitEntitlement` leest de handtekening
    /// en zou dan slagen, waarna `CKContainer(identifier:)` het proces afbreekt
    /// op een manier die niet te vangen is. Het standaardbestand, dat CI en elke
    /// verse checkout gebruiken, moet dus schoon blijven.
    func testStandaardEntitlementsDragenGeenRestrictedRechten() throws {
        let plist = try entitlements("WhisperClipboard.entitlements")
        let restricted = plist.keys.filter { $0.hasPrefix("com.apple.developer.") }
        XCTAssertTrue(
            restricted.isEmpty,
            "de standaardentitlements moeten minimaal blijven, gevonden: \(restricted)"
        )
        XCTAssertEqual(plist["com.apple.security.device.audio-input"] as? Bool, true,
                       "microfoontoegang hoort er wel in te staan")
    }

    // MARK: - De engine blijft slapend bij een onbekende container

    /// De guard faalt vóór `CKContainer` wordt aangeraakt, dus dit is veilig uit
    /// te voeren zonder iCloud-account. Het test precies het pad dat stil kapot
    /// was, inclusief de diagnose die er nu uit komt.
    func testOnbekendeContainerLevertEenLeesbareDiagnose() {
        let probleem = HistorySyncEngine.cloudKitEntitlementProblem(
            for: "iCloud.nl.nielscroiset.bestaat-niet"
        )
        XCTAssertNotNil(probleem, "een verzonnen container mag nooit als geldig gelden")
        XCTAssertFalse(
            probleem?.isEmpty ?? true,
            "de diagnose moet zeggen wát er ontbreekt, want dit is de enige aanwijzing in het log"
        )
    }
}
