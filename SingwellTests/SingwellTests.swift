import XCTest
import SingwellCore
@testable import Singwell

@MainActor
final class SingwellTests: XCTestCase {
    func testTakeLibraryRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("singwell-tests-\(UUID().uuidString)")
        let library = TakeLibrary(directory: dir)
        let url = library.newRecordingURL()
        try Data([0, 1, 2]).write(to: url)
        let take = Take(title: "Test", duration: 3, fileName: url.lastPathComponent, frames: [PitchFrame(t: 0, midi: 60, target: nil)], context: .sing)
        library.add(take)
        XCTAssertEqual(library.takes.count, 1)
        let reloaded = TakeLibrary(directory: dir)
        XCTAssertEqual(reloaded.takes.first?.title, "Test")
        reloaded.rename(take, to: "Renamed")
        XCTAssertEqual(reloaded.takes.first?.title, "Renamed")
        reloaded.delete(take)
        XCTAssertTrue(reloaded.takes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testEntitlementGates() {
        XCTAssertTrue(Entitlements.canSaveTake(count: 2, pro: false))
        XCTAssertFalse(Entitlements.canSaveTake(count: 3, pro: false))
        XCTAssertTrue(Entitlements.canSaveTake(count: 300, pro: true))
        XCTAssertTrue(Entitlements.canUseRoutine("quick", pro: false))
        XCTAssertFalse(Entitlements.canUseRoutine("full", pro: false))
        XCTAssertFalse(Entitlements.canUseQuestCount(12, pro: false))
        XCTAssertTrue(Entitlements.canUseQuestCount(5, pro: false))
    }

    func testSteadinessMeter() {
        let steady = (0..<20).map { (t: Double($0) * 0.07, midi: 60.02) }
        XCTAssertGreaterThan(PracticeSession.steadiness(of: steady) ?? 0, 0.9)
        var wobbly: [(t: Double, midi: Double)] = []
        for i in 0..<20 {
            let offset: Double = i % 2 == 0 ? 0.6 : -0.6
            wobbly.append((t: Double(i) * 0.07, midi: 60 + offset))
        }
        XCTAssertLessThan(PracticeSession.steadiness(of: wobbly) ?? 1, 0.2)
        XCTAssertNil(PracticeSession.steadiness(of: []))
    }
}
