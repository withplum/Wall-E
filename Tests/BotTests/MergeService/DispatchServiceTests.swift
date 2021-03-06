import XCTest
import Nimble
import ReactiveSwift
@testable import Bot

class DispatchServiceTests: XCTestCase {
    func test_multiple_pull_requests_with_different_target_branches() {

        let pullRequests = (1...3).map {
            PullRequestMetadata.stub(number: $0, baseRef: "branch\($0)", labels: [LabelFixture.integrationLabel])
                .with(mergeState: .clean)
        }
        func returnPR() -> (UInt) -> PullRequestMetadata {
            return { number in pullRequests[Int(number-1)] }
        }

        perform(
            stubs: [
                .getCurrentUser { nil },
                .getPullRequests { pullRequests.map { $0.reference } },
                .getIssueComments { _ in [] },
                .getIssueComments { _ in [] },
                .getIssueComments { _ in [] },
                .getPullRequest(returnPR()),
                .postComment { _, _ in },
                .getPullRequest(returnPR()),
                .postComment { _, _ in },
                .getPullRequest(returnPR()),
                .postComment { _, _ in },
                .mergePullRequest { _ in },
                .deleteBranch { _ in },
                .mergePullRequest { _ in },
                .deleteBranch { _ in },
                .mergePullRequest { _ in },
                .deleteBranch { _ in },
            ],
            when: { service, scheduler in
                scheduler.advance()
            },
            assert: { events in
                let perBranchEvents = Dictionary(grouping: events) { $0.branch }
                expect(perBranchEvents.count) == 3
                for (branch, events) in perBranchEvents {
                    let filteredPRs = pullRequests.filter { $0.reference.target.ref == branch }
                    expect(filteredPRs.count) == 1
                    let prForBranch = filteredPRs.first!
                    expect(events) == [
                        .created(branch: branch),
                        .state(.stub(targetBranch: branch, status: .starting)),
                        .state(.stub(targetBranch: branch, status: .ready, pullRequests: [prForBranch.reference])),
                        .state(.stub(targetBranch: branch, status: .integrating(prForBranch))),
                        .state(.stub(targetBranch: branch, status: .ready)),
                        .state(.stub(targetBranch: branch, status: .idle)),
                    ]
                }
            }
        )
    }

    func test_adding_new_pull_requests_during_integration() {
        let (developBranch, releaseBranch) = ("develop", "release/app/1.2.3")

        let dev1 = PullRequestMetadata.stub(number: 1, headRef: MergeServiceFixture.defaultBranch, baseRef: developBranch, labels: [LabelFixture.integrationLabel], mergeState: .behind)
        let dev2 = PullRequestMetadata.stub(number: 2, baseRef: developBranch, labels: [LabelFixture.integrationLabel], mergeState: .clean)
        let rel3 = PullRequestMetadata.stub(number: 3, baseRef: releaseBranch, labels: [LabelFixture.integrationLabel], mergeState: .clean)

        perform(
            stubs: [
                .getCurrentUser { nil },
                .getPullRequests { [dev1.reference] },
                .getIssueComments { _ in [] },
                .getPullRequest(checkReturnPR(dev1)),
                .postComment(checkComment(1, MergeService.acceptedCommentText(index: nil, queue: "develop", isBooting: true))),
                .mergeIntoBranch { head, base in
                    expect(head) == dev1.reference.source
                    expect(base) == dev1.reference.target
                    return .success
                },

                .postComment(checkComment(2, MergeService.acceptedCommentText(index: 0, queue: "develop"))),
                .getPullRequest(checkReturnPR(rel3)),
                .postComment(checkComment(3, MergeService.acceptedCommentText(index: nil, queue: "release/app/1.2.3"))),
                .mergePullRequest(checkPRNumber(3)),
                .deleteBranch(checkBranch(rel3.reference.source)),

                .getPullRequest(checkReturnPR(dev1.with(mergeState: .clean))),
                .getCommitStatus { pullRequest in
                    expect(pullRequest.number) == 1
                    return CommitState.stub(states: [.success])
                },

                .mergePullRequest(checkPRNumber(1)),
                .deleteBranch(checkBranch(dev1.reference.source)),
                .getPullRequest(checkReturnPR(dev2)),
                .mergePullRequest(checkPRNumber(2)),
                .deleteBranch(checkBranch(dev2.reference.source)),
            ],
            when: { service, scheduler in

                scheduler.advance()

                service.sendPullRequestEvent(action: .synchronize, pullRequestMetadata: dev1.with(mergeState: .blocked))

                scheduler.advance()

                service.sendPullRequestEvent(action: .labeled, pullRequestMetadata: dev2)

                scheduler.advance()

                service.sendPullRequestEvent(action: .labeled, pullRequestMetadata: rel3)

                scheduler.advance()

                service.sendStatusEvent(state: .success)
                scheduler.advance(by: DispatchServiceContext.additionalStatusChecksGracePeriod)

                // Let the services stay .idle for the cleanup delay so they end up being destroyed
                scheduler.advance(by: DispatchServiceContext.idleCleanupDelay)
            },
            assert: {
                expect($0) == [
                    .created(branch: developBranch),
                    .state(.stub(targetBranch: developBranch, status: .starting)),
                    .state(.stub(targetBranch: developBranch, status: .ready, pullRequests: [dev1.reference])),
                    .state(.stub(targetBranch: developBranch, status: .integrating(dev1))),
                    .state(.stub(targetBranch: developBranch, status: .runningStatusChecks(dev1.with(mergeState: .blocked)))),
                    .state(.stub(targetBranch: developBranch, status: .runningStatusChecks(dev1.with(mergeState: .blocked)), pullRequests: [dev2.reference])),

                    .created(branch: releaseBranch),
                    .state(.stub(targetBranch: releaseBranch, status: .idle)),
                    .state(.stub(targetBranch: releaseBranch, status: .ready, pullRequests: [rel3.reference])),
                    .state(.stub(targetBranch: releaseBranch, status: .integrating(rel3))),
                    .state(.stub(targetBranch: releaseBranch, status: .ready)),
                    .state(.stub(targetBranch: releaseBranch, status: .idle)),

                    .state(.stub(targetBranch: developBranch, status: .integrating(dev1.with(mergeState: .clean)), pullRequests: [dev2.reference])),
                    .state(.stub(targetBranch: developBranch, status: .ready, pullRequests: [dev2.reference])),
                    .state(.stub(targetBranch: developBranch, status: .integrating(dev2))),
                    .state(.stub(targetBranch: developBranch, status: .ready)),
                    .state(.stub(targetBranch: developBranch, status: .idle)),

                    .destroyed(branch: releaseBranch),
                    .destroyed(branch: developBranch),
                ]
            }
        )
    }

    func test_creating_new_pull_requests_to_new_target_branch_without_label() {
        let (developBranch, releaseBranch) = ("develop", "release/app/1.2.3")

        let dev1 = PullRequestMetadata.stub(number: 1, headRef: MergeServiceFixture.defaultBranch, baseRef: developBranch, labels: [LabelFixture.integrationLabel], mergeState: .behind)
        let dev2 = PullRequestMetadata.stub(number: 2, baseRef: developBranch, labels: [LabelFixture.integrationLabel], mergeState: .clean)
        let rel3 = PullRequestMetadata.stub(number: 3, baseRef: releaseBranch, mergeState: .clean)

        perform(
            stubs: [
                .getCurrentUser { nil },
                .getPullRequests { [dev1.reference] },
                .getIssueComments { _ in [] },
                .getPullRequest(checkReturnPR(dev1)),
                .postComment(checkComment(1, MergeService.acceptedCommentText(index: nil, queue: "develop", isBooting: true))),
                .mergeIntoBranch { head, base in
                    expect(head.ref) == MergeServiceFixture.defaultBranch
                    expect(base.ref) == developBranch
                    return .success
                },

                .postComment(checkComment(2, MergeService.acceptedCommentText(index: 0, queue: "develop"))),

                // Note that here we shouldn't have any API call for PR#3 since it doesn't have the integration label
                
                .getPullRequest(checkReturnPR(dev1.with(mergeState: .clean))),
                .getCommitStatus { pullRequest in
                    expect(pullRequest.number) == 1
                    return CommitState.stub(states: [.success])
                },

                .mergePullRequest(checkPRNumber(1)),
                .deleteBranch(checkBranch(dev1.reference.source)),
                .getPullRequest(checkReturnPR(dev2)),
                .mergePullRequest(checkPRNumber(2)),
                .deleteBranch(checkBranch(dev2.reference.source)),
            ],
            when: { service, scheduler in

                scheduler.advance()

                service.sendPullRequestEvent(action: .synchronize, pullRequestMetadata: dev1.with(mergeState: .blocked))

                scheduler.advance()

                service.sendPullRequestEvent(action: .labeled, pullRequestMetadata: dev2)

                scheduler.advance()

                service.sendPullRequestEvent(action: .opened, pullRequestMetadata: rel3)

                scheduler.advance()

                service.sendStatusEvent(state: .success)

                scheduler.advance(by: DispatchServiceContext.additionalStatusChecksGracePeriod)

                scheduler.advance(by: DispatchServiceContext.idleCleanupDelay)
            },
            assert: {
                expect($0) == [
                    .created(branch: developBranch),
                    .state(.stub(targetBranch: developBranch, status: .starting)),
                    .state(.stub(targetBranch: developBranch, status: .ready, pullRequests: [dev1.reference])),
                    .state(.stub(targetBranch: developBranch, status: .integrating(dev1))),
                    .state(.stub(targetBranch: developBranch, status: .runningStatusChecks(dev1.with(mergeState: .blocked)))),
                    .state(.stub(targetBranch: developBranch, status: .runningStatusChecks(dev1.with(mergeState: .blocked)), pullRequests: [dev2.reference])),

                    .created(branch: releaseBranch),
                    // Since the new PR got filtered out for not having the integration label, there's nothing to be done
                    // and this new MergeService for that release branch will soon be destroyed at the end for inactivity
                    .state(.stub(targetBranch: releaseBranch, status: .idle)),

                    .state(.stub(targetBranch: developBranch, status: .integrating(dev1.with(mergeState: .clean)), pullRequests: [dev2.reference])),
                    .state(.stub(targetBranch: developBranch, status: .ready, pullRequests: [dev2.reference])),
                    .state(.stub(targetBranch: developBranch, status: .integrating(dev2))),
                    .state(.stub(targetBranch: developBranch, status: .ready)),
                    .state(.stub(targetBranch: developBranch, status: .idle)),

                    .destroyed(branch: releaseBranch),
                    .destroyed(branch: developBranch)
                ]
            }
        )
    }

    func test_mergeservice_not_destroyed_if_not_idle_long_enough() {
        test_mergeservice_watchdog(advancePastTheDelay: false)
    }

    func test_mergeservice_destroyed_if_idle_long_enough() {
        test_mergeservice_watchdog(advancePastTheDelay: true)
    }

    fileprivate func test_mergeservice_watchdog(advancePastTheDelay: Bool) {
        // 3/4th of cleanup time (i.e. a little less than the delay but would still go past the delay once advanced a second time)
        let almostCleanupDelay: DispatchTimeInterval = .milliseconds(Int(MergeServiceFixture.defaultIdleCleanupDelay * 750.0))

        let prs = [1,2,3].map { PullRequestMetadata.stub(number: UInt($0), labels: [LabelFixture.integrationLabel], mergeState: .clean) }

        perform(
            stubs: [
                .getCurrentUser { nil },
                .getPullRequests { [prs[0].reference] },
                .getIssueComments { _ in [] },
                .getPullRequest { _ in prs[0] },
                .postComment { _, _ in },
                .mergePullRequest { _ in },
                .deleteBranch { _ in },

                .getPullRequest { _ in prs[1].with(mergeState: .blocked) },
                .postComment { _, _ in },
                .getAllStatusChecks { _ in [.init(state: .pending, context: "Test 1", description: "")] },

                .getPullRequest { _ in prs[2] },
                .postComment { _, _ in },
                .mergePullRequest { _ in },
                .deleteBranch { _ in },
            ],
            when: { service, scheduler in

                // Start the state machine and integrate PR #1 (starting -> ready -> integrating -> ready -> idle)
                scheduler.advance()
                service.sendPullRequestEvent(action: .synchronize, pullRequestMetadata: prs[0])
                scheduler.advance()

                // Current state: idle

                // Wait a bit before labelling the next PR
                scheduler.advance(by: almostCleanupDelay)

                // Start integrating PR #2 but keep it too long in status checks
                // ( -> ready -> integrating -> runningStatusChecks -> 🕓 -> ❌ -> ready -> idle)
                service.sendPullRequestEvent(action: .labeled, pullRequestMetadata: prs[1].with(mergeState: .blocked))
                scheduler.advance()

                // Stay a bit in state .runningStatusChecks
                scheduler.advance(by: almostCleanupDelay)
                scheduler.advance(by: almostCleanupDelay)

                // Then close it
                service.sendPullRequestEvent(action: .closed, pullRequestMetadata: prs[1])
                scheduler.advance()

                // Current state: idle

                // Wait a bit before labelling the next PR
                scheduler.advance(by: almostCleanupDelay)

                // Integrate PR #3 ( -> ready -> integrating -> ready -> idle)
                service.sendPullRequestEvent(action: .labeled, pullRequestMetadata: prs[2])

                scheduler.advance(by: almostCleanupDelay)

                if advancePastTheDelay {
                    scheduler.advance(by: almostCleanupDelay)
                }
            },
            assert: {
                var expected: [DispatchServiceEvent] = [
                    .created(branch: MergeServiceFixture.defaultTargetBranch),
                    .state(.stub(status: .starting)),

                    .state(.stub(status: .ready, pullRequests: [prs[0].reference])),
                    .state(.stub(status: .integrating(prs[0]))),
                    .state(.stub(status: .ready)),
                    .state(.stub(status: .idle)),

                    .state(.stub(status: .ready, pullRequests: [prs[1].reference])),
                    .state(.stub(status: .integrating(prs[1].with(mergeState: .blocked)))),
                    .state(.stub(status: .runningStatusChecks(prs[1].with(mergeState: .blocked)))),
                    // The main point of the test is to ensure we DONT .destroy the MergeService at this point
                    .state(.stub(status: .ready)),
                    .state(.stub(status: .idle)),

                    .state(.stub(status: .ready, pullRequests: [prs[2].reference])),
                    .state(.stub(status: .integrating(prs[2]))),
                    .state(.stub(status: .ready)),
                    .state(.stub(status: .idle))
                ]
                if advancePastTheDelay {
                    expected.append(.destroyed(branch: MergeServiceFixture.defaultTargetBranch))
                }
                expect($0) == expected
            }
        )
    }

    func test_mergeservice_destroyed_when_idle_after_boot() {
        let pr = PullRequestMetadata.stub(number: 1) // No Merge label, so should get filtered out
        let branch = pr.reference.target.ref

        perform(
            stubs: [
                .getCurrentUser { nil },
                .getPullRequests { [pr.reference] },
            ],
            when: { service, scheduler in
                scheduler.advance(by: DispatchServiceContext.idleCleanupDelay)
            },
            assert: {
                expect($0) == [
                    .created(branch: branch),
                    .state(.stub(targetBranch: branch, status: .idle)),
                    .destroyed(branch: branch)
                ]
            }
        )
    }

    func test_queue_description() throws {
        let (branch1, branch2) = ("branch1", "branch2")
        let pr1 = PullRequestMetadata.stub(number: 1, headRef: MergeServiceFixture.defaultBranch, baseRef: branch1, labels: [LabelFixture.integrationLabel], mergeState: .behind)
        let pr2 = PullRequestMetadata.stub(number: 2, baseRef: branch1, labels: [LabelFixture.integrationLabel], mergeState: .clean)
        let pr3 = PullRequestMetadata.stub(number: 3, baseRef: branch2, labels: [LabelFixture.integrationLabel], mergeState: .behind)

        let stubs: [MockGitHubAPI.Stubs] = [
            .getCurrentUser { nil },
            .getPullRequests { [pr1.reference] },
            .getIssueComments { _ in [] },
            .getPullRequest(checkReturnPR(pr1)),
            .postComment(checkComment(1, MergeService.acceptedCommentText(index: nil, queue: "branch1", isBooting: true))),
            .mergeIntoBranch { _, _ in .success },
            .postComment(checkComment(2, MergeService.acceptedCommentText(index: 0, queue: "branch1"))),
            .getPullRequest(checkReturnPR(pr3)),
            .postComment(checkComment(3, MergeService.acceptedCommentText(index: nil, queue: "branch2"))),
            .mergeIntoBranch { _, _ in .success },
        ]

        let scheduler = TestScheduler()
        let gitHubAPI = MockGitHubAPI(stubs: stubs)
        let gitHubEvents = MockGitHubEventsService()

        let dispatchServiceContext = DispatchServiceContext(
            requiresAllStatusChecks: true,
            gitHubAPI: gitHubAPI,
            gitHubEvents: gitHubEvents,
            scheduler: scheduler
        )

        expect(dispatchServiceContext.dispatchService.queueStates) == []

        scheduler.advance()
        gitHubEvents.sendPullRequestEvent(action: .labeled, pullRequestMetadata: pr2)
        scheduler.advance()
        gitHubEvents.sendPullRequestEvent(action: .labeled, pullRequestMetadata: pr3)
        scheduler.advance()

        let jsonData = try JSONEncoder().encode(dispatchServiceContext.dispatchService.queueStates)
        XCTAssertEqualJSON(jsonData, DispatchServiceQueueStatesJSON)
        XCTAssertEqual(dispatchServiceContext.dispatchService.queuesDescription, DispatchServiceQueueStatesString)
    }
}

// MARK: - Helpers

extension DispatchServiceTests {
    private func checkComment(_ expectedPRNumber: UInt, _ expectedMessage: String, file: FileString = #file, line: UInt = #line) -> (String, PullRequest) -> Void {
        return { message, pullRequest in
            expect(pullRequest.number, file: file, line: line) == expectedPRNumber
            expect(message, file: file, line: line) == expectedMessage
        }
    }

    private func checkReturnPR(_ prToReturn: PullRequestMetadata, file: FileString = #file, line: UInt = #line) -> (UInt) -> PullRequestMetadata {
        return { number in
            expect(number, file: file, line: line) == prToReturn.reference.number
            return prToReturn
        }
    }

    private func checkPRNumber(_ expectedNumber: UInt, file: FileString = #file, line: UInt = #line) -> (PullRequest) -> Void {
        return { pullRequest in
            expect(pullRequest.number, file: file, line: line) == expectedNumber
        }
    }

    private func checkBranch(_ expectedBranch: PullRequest.Branch, file: FileString = #file, line: UInt = #line) -> (PullRequest.Branch) -> Void {
        return { branch in
            expect(branch.ref, file: file, line: line) == expectedBranch.ref
        }
    }

    private func perform(
        requiresAllStatusChecks: Bool = false,
        stubs: [MockGitHubAPI.Stubs],
        when: (MockGitHubEventsService, TestScheduler) -> Void,
        assert: ([DispatchServiceEvent]) -> Void
    ) {

        let scheduler = TestScheduler()
        let gitHubAPI = MockGitHubAPI(stubs: stubs)
        let gitHubEvents = MockGitHubEventsService()

        let dispatchServiceContext = DispatchServiceContext(
            requiresAllStatusChecks: requiresAllStatusChecks,
            gitHubAPI: gitHubAPI,
            gitHubEvents: gitHubEvents,
            scheduler: scheduler
        )

        when(gitHubEvents, scheduler)

        assert(dispatchServiceContext.events)

        expect(gitHubAPI.assert()) == true
    }
}
