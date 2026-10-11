import Testing
@testable import EdgeWakeCore

@Suite struct SideLearnerTests {
    @Test func pointerLeavingLeftAndEnteringPeersRightMeansPeerIsOnTheLeft() {
        var learner = SideLearner()
        learner.localTouchedEdge(.left, at: 10.0)
        #expect(learner.peerReportedEntry(from: .right, at: 10.3) == .left)
    }

    @Test func entryOnTheSameSideIsInconsistent() {
        var learner = SideLearner()
        learner.localTouchedEdge(.left, at: 10.0)
        #expect(learner.peerReportedEntry(from: .left, at: 10.3) == nil)
    }

    @Test func entryTooLongAfterTheTouchIsIgnored() {
        var learner = SideLearner()
        learner.localTouchedEdge(.right, at: 10.0)
        #expect(learner.peerReportedEntry(from: .left, at: 11.0) == nil)
    }

    @Test func movingAwayFromTheEdgeClearsTheCandidate() {
        var learner = SideLearner()
        learner.localTouchedEdge(.left, at: 10.0)
        learner.localMovedAway(at: 10.1)
        #expect(learner.peerReportedEntry(from: .right, at: 10.2) == nil)
    }

    @Test func aPinnedPointerKeepsTheCandidateFresh() {
        var learner = SideLearner()
        learner.localTouchedEdge(.left, at: 10.0)
        learner.localTouchedEdge(.left, at: 12.0)
        #expect(learner.peerReportedEntry(from: .right, at: 12.4) == .left)
    }

    @Test func aCandidateIsUsedOnce() {
        var learner = SideLearner()
        learner.localTouchedEdge(.left, at: 10.0)
        #expect(learner.peerReportedEntry(from: .right, at: 10.2) == .left)
        #expect(learner.peerReportedEntry(from: .right, at: 10.3) == nil)
    }
}
