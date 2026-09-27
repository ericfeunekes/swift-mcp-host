import MCPHostCore
import Testing

@Suite struct ProtocolRevisionTests {
    @Test func erasMatchTheDualEraContract() {
        #expect(ProtocolRevision.allCases.filter { $0.era == .modern } == [.v2026_07_28])
        #expect(ProtocolRevision.allCases.filter { $0.era == .legacy } == [.v2025_03_26, .v2025_06_18, .v2025_11_25])
    }

    @Test func initializeCounterOfferIsTheNewestLegacyRevision() {
        let legacy = ProtocolRevision.allCases.filter { $0.era == .legacy }
        #expect(ProtocolRevision.latestLegacy == legacy.max())
    }

    @Test func orderingFollowsRevisionDates() {
        #expect(ProtocolRevision.allCases.sorted() == [.v2025_03_26, .v2025_06_18, .v2025_11_25, .v2026_07_28])
    }
}
