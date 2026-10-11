import Foundation
import Testing
@testable import EdgeWakeCore

@Suite struct WakeSchedulerTests {
    private let mini = UUID()
    private let studio = UUID()

    private func peer(_ id: UUID, side: Side?, online: Bool = true, asleep: Bool = true) -> WakeCandidate {
        WakeCandidate(id: id, side: side, isOnline: online, displayAsleep: asleep)
    }

    @Test func wakesSleepingPeersOnTheGestureSide() {
        var scheduler = WakeScheduler()
        let decision = scheduler.decide(gestureOn: .left, peers: [peer(mini, side: .left), peer(studio, side: .right)], now: 0)
        #expect(decision == .wake([mini]))
    }

    @Test func aPeerWithUnknownSideAnswersEitherEdge() {
        var scheduler = WakeScheduler()
        let decision = scheduler.decide(gestureOn: .right, peers: [peer(mini, side: nil)], now: 0)
        #expect(decision == .wake([mini]))
    }

    @Test func awakeOrOfflinePeersAreNotWoken() {
        var scheduler = WakeScheduler()
        let peers = [peer(mini, side: .left, asleep: false), peer(studio, side: nil, online: false)]
        let decision = scheduler.decide(gestureOn: .left, peers: peers, now: 0)
        #expect(decision == .nothing)
    }

    @Test func cooldownStartsAtTheAcknowledgement() {
        var scheduler = WakeScheduler()
        let wake = UUID()
        scheduler.sent(wake, to: mini, at: 0)
        let answeredBy = scheduler.acknowledged(wake, at: 1)
        #expect(answeredBy == mini)
        let beforeCooldown = scheduler.decide(gestureOn: .left, peers: [peer(mini, side: .left)], now: 10.5)
        #expect(beforeCooldown == .nothing)
        let afterCooldown = scheduler.decide(gestureOn: .left, peers: [peer(mini, side: .left)], now: 11.5)
        #expect(afterCooldown == .wake([mini]))
    }

    @Test func anUnansweredWakeCanBeRetriedAfterItTimesOut() {
        var scheduler = WakeScheduler()
        scheduler.sent(UUID(), to: mini, at: 0)
        let whilePending = scheduler.decide(gestureOn: .left, peers: [peer(mini, side: .left)], now: 1)
        #expect(whilePending == .nothing)
        let afterTimeout = scheduler.decide(gestureOn: .left, peers: [peer(mini, side: .left)], now: 4.5)
        #expect(afterTimeout == .wake([mini]))
    }

    @Test func aLateOrUnknownAcknowledgementIsIgnored() {
        var scheduler = WakeScheduler()
        let wake = UUID()
        scheduler.sent(wake, to: mini, at: 0)
        _ = scheduler.decide(gestureOn: .left, peers: [], now: 5) // expires the pending wake
        let late = scheduler.acknowledged(wake, at: 5)
        #expect(late == nil)
        let unknown = scheduler.acknowledged(UUID(), at: 5)
        #expect(unknown == nil)
    }

    @Test func offlinePeerOnThatSideIsReportedOncePerCooldown() {
        var scheduler = WakeScheduler()
        let peers = [peer(mini, side: .left, online: false)]
        let first = scheduler.decide(gestureOn: .left, peers: peers, now: 0)
        #expect(first == .reportOffline(mini))
        let withinCooldown = scheduler.decide(gestureOn: .left, peers: peers, now: 5)
        #expect(withinCooldown == .nothing)
        let afterCooldown = scheduler.decide(gestureOn: .left, peers: peers, now: 11)
        #expect(afterCooldown == .reportOffline(mini))
    }

    @Test func offlinePeerWithUnknownSideIsNotReported() {
        var scheduler = WakeScheduler()
        let decision = scheduler.decide(gestureOn: .left, peers: [peer(mini, side: nil, online: false)], now: 0)
        #expect(decision == .nothing)
    }

    @Test func pendingCountsAsWakingUntilAnswered() {
        var scheduler = WakeScheduler()
        let wake = UUID()
        scheduler.sent(wake, to: mini, at: 0)
        let pending = scheduler.hasPendingWakes(at: 1)
        #expect(pending)
        _ = scheduler.acknowledged(wake, at: 1)
        let pendingAfterAnswer = scheduler.hasPendingWakes(at: 1)
        #expect(!pendingAfterAnswer)
    }
}
