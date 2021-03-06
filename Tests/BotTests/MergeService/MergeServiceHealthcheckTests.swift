import XCTest
import Nimble
import ReactiveSwift
@testable import Bot

class MergeServiceHealthcheckTests: XCTestCase {

    func test_healthcheck_passing() {

        perform(
            when: { input, scheduler in
                scheduler.advance()

                input.send(value: MergeService.State.stub(status: .starting))

                scheduler.advance()

                input.send(value: MergeService.State.stub(status: .idle))

                scheduler.advance()

                input.send(value: MergeService.State.stub(status: .ready))

                scheduler.advance()

                input.send(value: MergeService.State.stub(status: .integrating(MergeServiceFixture.defaultTarget)))

                scheduler.advance()

                input.send(value: MergeService.State.stub(status: .ready))

                scheduler.advance()

                input.send(value: MergeService.State.stub(status: .idle))

                scheduler.advance()
            },
            assert: { statuses in
                expect(statuses) == [.ok, .ok, .ok]
            }
        )
    }

    func test_healthcheck_failing() {

        perform(
            when: { input, scheduler in

                scheduler.advance()

                input.send(value: MergeService.State.stub(status: .starting))

                scheduler.advance()

                input.send(value: MergeService.State.stub(status: .idle))

                scheduler.advance()

                input.send(value: MergeService.State.stub(status: .ready))

                scheduler.advance()

                input.send(value: MergeService.State.stub(status: .runningStatusChecks(MergeServiceFixture.defaultTarget)))

                scheduler.advance(by: .minutes(2 * MergeServiceFixture.defaultStatusChecksTimeout))

                input.send(value: MergeService.State.stub(status: .integrationFailed(MergeServiceFixture.defaultTarget, .checksFailing)))

                scheduler.advance()

                input.send(value: MergeService.State.stub(status: .ready))
                input.send(value: MergeService.State.stub(status: .idle))

                scheduler.advance()

            },
            assert: { statuses in
                expect(statuses) == [.ok, .ok, .unhealthy(.potentialDeadlock), .ok]
            }
        )
    }

    private func perform(
        when: (Signal<MergeService.State, Never>.Observer, TestScheduler) -> Void,
        assert: ([MergeService.Healthcheck.Status]) -> Void
    ) {
        let state = Signal<MergeService.State, Never>.pipe()
        let scheduler = TestScheduler()

        var statuses: [MergeService.Healthcheck.Status] = []

        let healthcheck = MergeService.Healthcheck(
            state: state.output,
            statusChecksTimeout: MergeServiceFixture.defaultStatusChecksTimeout,
            scheduler: scheduler
        )

        healthcheck.status.producer.startWithValues { status in
            statuses.append(status)
        }

        when(state.input, scheduler)
        assert(statuses)
    }
}
