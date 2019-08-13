import Foundation
import Result
import ReactiveSwift
import ReactiveFeedback

public final class MergeService {
    let state: Property<State>

    private let logger: LoggerProtocol
    private let github: GitHubAPIProtocol
    private let scheduler: DateScheduler

    private let pullRequestChanges: Signal<(PullRequestMetadata, PullRequest.Action), NoError>
    private let pullRequestChangesObserver: Signal<(PullRequestMetadata, PullRequest.Action), NoError>.Observer

    private let statusChecksCompletion: Signal<StatusChange, NoError>
    private let statusChecksCompletionObserver: Signal<StatusChange, NoError>.Observer

    public init(
        integrationLabel: PullRequest.Label,
        statusChecksTimeout: TimeInterval = 60.minutes,
        logger: LoggerProtocol,
        github: GitHubAPIProtocol,
        scheduler: DateScheduler = QueueScheduler()
    ) {

        self.logger = logger
        self.github = github
        self.scheduler = scheduler

        (statusChecksCompletion, statusChecksCompletionObserver) = Signal.pipe()

        (pullRequestChanges, pullRequestChangesObserver) = Signal.pipe()

        state = Property<State>(
            initial: State.initial(with: integrationLabel, statusChecksTimeout: statusChecksTimeout),
            scheduler: scheduler,
            reduce: MergeService.reduce,
            feedbacks: [
                Feedbacks.whenStarting(github: self.github, scheduler: scheduler),
                Feedbacks.whenReady(github: self.github, scheduler: scheduler),
                Feedbacks.whenIntegrating(github: self.github, pullRequestChanges: pullRequestChanges, scheduler: scheduler),
                Feedbacks.whenRunningStatusChecks(github: self.github, logger: logger, statusChecksCompletion: statusChecksCompletion, scheduler: scheduler),
                Feedbacks.whenIntegrationFailed(github: self.github, logger: logger, scheduler: scheduler),
                Feedbacks.pullRequestChanges(pullRequestChanges: pullRequestChanges, scheduler: scheduler),
                Feedbacks.whenAddingPullRequests(github: self.github, scheduler: scheduler)
            ]
        )

        state.producer
            .combinePrevious()
            .startWithValues { old, new in
                logger.log("♻️ [Merge Service] Did change state\n - 📜 \(old) \n - 📄 \(new)")
            }
    }

    func pullRequestDidChange(metadata: PullRequestMetadata, action: PullRequest.Action) {
        logger.log("📣 [Merge Service] Pull Request did change \(metadata) with action `\(action)`")
        pullRequestChangesObserver.send(value: (metadata, action))
    }

    func statusChecksDidChange(change: StatusChange) {
        statusChecksCompletionObserver.send(value: change)
    }

    static func reduce(state: State, event: Event) -> State {

        let reducedState: State? = {
            switch state.status {
            case .idle:
                return state.reduceIdle(with: event)
            case .starting:
                return state.reduceStarting(with: event)
            case .ready:
                return state.reduceReady(with: event)
            case let .integrating(metadata):
                return state.reduceIntegrating(with: metadata, event: event)
            case let .runningStatusChecks(metadata):
                return state.reduceRunningStatusChecks(with: metadata, event: event)
            case .integrationFailed:
                return state.reduceIntegrationFailed(with: event)
            }
        }()

        return reducedState ?? state.reduceDefault(with: event)
    }
}

// MARK: - Feedbacks

extension MergeService {
    fileprivate typealias Feedbacks = MergeService

    fileprivate static func whenAddingPullRequests(
        github: GitHubAPIProtocol,
        scheduler: Scheduler
    ) -> Feedback<State, Event> {

        return Feedback(
            deriving: { state in state.combinePrevious() },
            effects: { previous, current -> SignalProducer<Event, NoError> in

                let actions = current.pullRequests
                    .enumerated()
                    .map { index, pullRequest -> SignalProducer<(), NoError> in

                        guard previous.pullRequests.firstIndex(of: pullRequest) == nil
                            else { return .empty }

                        switch index {
                        case 0:
                            return github.postComment(
                                "Your pull request was accepted and is going to be handled right away 🏎",
                                in: pullRequest
                                )
                                .flatMapError { _ in .empty }
                        case 1...:
                            return github.postComment(
                                "Your pull request was accepted and it's currently `#\(index + 1)` in the queue, hold tight ⏳",
                                in: pullRequest
                                )
                                .flatMapError { _ in .empty }
                        default:
                            return .empty
                        }
                }

                return SignalProducer.merge(actions)
                    .then(.empty)
        })
    }

    fileprivate static func whenStarting(github: GitHubAPIProtocol, scheduler: Scheduler) -> Feedback<State, Event> {
        return Feedback(predicate: { $0.status == .starting }) { state -> SignalProducer<Event, NoError> in

            return github.fetchPullRequests()
                .flatMapError { _ in .value([]) }
                .map { pullRequests in
                    pullRequests.filter { $0.isLabelled(with: state.integrationLabel) }
                }
                .map(Event.pullRequestsLoaded)
                .start(on: scheduler)
        }
    }

    fileprivate static func whenReady(github: GitHubAPIProtocol, scheduler: Scheduler) -> Feedback<State, Event> {
        return Feedback(predicate: { $0.status == .ready }) { state -> SignalProducer<Event, NoError> in

            guard let next = state.pullRequests.first
                else { return .value(.noMorePullRequests) }

            // Refresh pull request to ensure an up-to-date state
            return github.fetchPullRequest(number: next.number)
                .flatMapError { _ in .empty }
                .map(Event.integrate)
                .observe(on: scheduler)
        }
    }

    fileprivate static func whenIntegrating(
        github: GitHubAPIProtocol,
        pullRequestChanges: Signal<(PullRequestMetadata, PullRequest.Action), NoError>,
        scheduler: DateScheduler
    ) -> Feedback<State, Event> {

        enum IntegrationError: Error {
            case stateCouldNotBeDetermined
            case synchronizationFailed
        }

        return Feedback(skippingRepeated: { $0.status.integrationMetadata }) { metadata -> SignalProducer<Event, NoError> in

            guard metadata.isMerged == false
                else { return .value(.integrationDidChangeStatus(.done, metadata)) }

            switch metadata.mergeState {
            case .clean:
                return github.mergePullRequest(metadata.reference)
                    .flatMap(.latest) { () -> SignalProducer<(), NoError> in
                        github.deleteBranch(named: metadata.reference.source)
                            .flatMapError { _ in .empty }
                    }
                    .then(SignalProducer<Event, NoError>.value(Event.integrationDidChangeStatus(.done, metadata)))
                    .flatMapError { _ in .value(Event.integrationDidChangeStatus(.failed(.mergeFailed), metadata)) }
                    .observe(on: scheduler)
            case .behind:
                return github.merge(head: metadata.reference.target, into: metadata.reference.source)
                    .flatMap(.latest) { result -> SignalProducer<Event, AnyError> in
                        switch result {
                        case .success:
                            return pullRequestChanges.filter { changedMetadata, action in
                                    action == .synchronize
                                        && changedMetadata.reference.source.ref == metadata.reference.source.ref
                                }
                                .producer
                                .take(first: 1)
                                .map { changedMetadata, _ in
                                    Event.integrationDidChangeStatus(.updating, changedMetadata)
                                }
                                .promoteError()
                                .timeout(
                                    after: 60.0,
                                    raising: AnyError(IntegrationError.synchronizationFailed), on: scheduler
                                )
                        case .upToDate:
                            return .value(.integrationDidChangeStatus(.updating, metadata))
                        case .conflict:
                            return .value(.integrationDidChangeStatus(.failed(.conflicts), metadata))
                        }
                    }
                    .flatMapError { _ in .value(.integrationDidChangeStatus(.failed(.synchronizationFailed), metadata)) }
                    .observe(on: scheduler)
            case .blocked,
                 .unstable:
                return github.fetchCommitStatus(for: metadata.reference)
                    .flatMap(.latest) { commitStatus -> SignalProducer<Event, AnyError> in
                        switch commitStatus.state {
                        case .pending:
                            return .value(.integrationDidChangeStatus(.updating, metadata))
                        case .failure:
                            return .value(.integrationDidChangeStatus(.failed(.checkingCommitChecksFailed), metadata))
                        case  .success:
                            return github.fetchPullRequest(number: metadata.reference.number)
                                .map { metadata in
                                    switch metadata.mergeState {
                                    case .clean:
                                        return .retryIntegration(metadata)
                                    default:
                                        return .integrationDidChangeStatus(.failed(.blocked), metadata)
                                    }
                            }
                        }
                    }
                    .flatMapError { _ in .value(Event.integrationDidChangeStatus(.failed(.checkingCommitChecksFailed), metadata)) }
                    .observe(on: scheduler)
            case .dirty:
                return SignalProducer(value: Event.integrationDidChangeStatus(.failed(.conflicts), metadata))
                    .observe(on: scheduler)
            case .unknown:
                return SignalProducer<Event, IntegrationError> { observer, _ in
                    github.fetchPullRequest(number: metadata.reference.number)
                        .take(first: 1)
                        .startWithResult {
                            switch $0 {
                            case let .success(metadata):
                                if metadata.mergeState == .unknown {
                                    observer.send(error: IntegrationError.stateCouldNotBeDetermined)
                                } else {
                                    observer.send(value: Event.retryIntegration(metadata))
                                    observer.sendCompleted()
                                }
                            case .failure:
                                observer.send(error: IntegrationError.stateCouldNotBeDetermined)
                            }
                        }
                    }
                    .retry(upTo: 4, interval: 30.0, on: scheduler)
                    .flatMapError { _ in .value(Event.integrationDidChangeStatus(.failed(.unknown), metadata)) }

            }
        }
    }

    fileprivate static func whenRunningStatusChecks(
        github: GitHubAPIProtocol,
        logger: LoggerProtocol,
        statusChecksCompletion: Signal<StatusChange, NoError>,
        scheduler: DateScheduler
    ) -> Feedback<State, Event> {

        struct Context: Equatable {
            let pullRequestMetadata: PullRequestMetadata
            let statusChecksTimeout: TimeInterval

            init?(state: State) {
                guard let metadata = state.status.statusChecksMetadata
                    else { return nil }

                self.pullRequestMetadata = metadata
                self.statusChecksTimeout = state.statusChecksTimeout
            }
        }

        return Feedback(skippingRepeated: Context.init) { context -> Signal<Event, NoError> in

            enum TimeoutError: Error {
                case timedOut
            }

            let pullRequest = context.pullRequestMetadata.reference

            return statusChecksCompletion
                .observe(on: scheduler)
                .filter { change in change.state != .pending && change.isRelative(toBranch: pullRequest.source.ref) }
                .on { change in
                    logger.log("📣 [Merge Service] Status check `\(change.context)` finished with result: `\(change.state)` (SHA: `\(change.sha)`)")
                }
                // Checks can complete and lead to new checks which can be included posteriorly leading to a small time
                // window where all checks have passed but just until the next check is added and stars running. This
                // hopefully prevents those false positives by making sure we wait some time before checking if all
                // checks have passed
                .debounce(60, on: scheduler)
                .flatMap(.latest) { change in
                    github.fetchPullRequest(number: pullRequest.number)
                        .flatMap(.latest) { github.fetchCommitStatus(for: $0.reference).zip(with: .value($0)) }
                        .flatMapError { _ in .empty }
                        .filterMap { commitStatus, pullRequestMetadataRefreshed in
                            switch commitStatus.state {
                            case .pending:
                                return nil
                            case .failure:
                                return .statusChecksDidComplete(.failed(pullRequestMetadataRefreshed))
                            case .success:
                                return .statusChecksDidComplete(.passed(pullRequestMetadataRefreshed))
                            }
                    }
                }
                .timeout(after: context.statusChecksTimeout, raising: TimeoutError.timedOut, on: scheduler)
                .flatMapError { error in
                    switch error {
                    case .timedOut: return .value(.statusChecksDidComplete(.failed(context.pullRequestMetadata)))
                    }
                }
        }
    }

    fileprivate static func whenIntegrationFailed(
        github: GitHubAPIProtocol,
        logger: LoggerProtocol,
        scheduler: Scheduler
    ) -> Feedback<State, Event> {

        struct IntegrationHandler: Equatable {
            let pullRequest: PullRequest
            let integrationLabel: PullRequest.Label
            let failureReason: FailureReason

            var failureMessage: String {
                return "@\(pullRequest.author.login) unfortunately the integration failed with code: `\(failureReason)`."
            }

            init?(from state: State) {
                guard case let .integrationFailed(metadata, reason) = state.status
                    else { return nil }
                self.pullRequest = metadata.reference
                self.integrationLabel = state.integrationLabel
                self.failureReason = reason
            }
        }

        return Feedback(skippingRepeated: IntegrationHandler.init) { handler -> SignalProducer<Event, NoError> in
            return SignalProducer.merge(
                github.postComment(handler.failureMessage, in: handler.pullRequest)
                    .on(failed: { error in logger.log("🚨 Failed to post failure message in PR #\(handler.pullRequest.number) with error: \(error)") }),
                github.removeLabel(handler.integrationLabel, from: handler.pullRequest)
                    .on(failed: { error in logger.log("🚨 Failed to remove integration label from PR #\(handler.pullRequest.number) with error: \(error)") })
                )
                .flatMapError { _ in .empty }
                .then(SignalProducer(value: Event.integrationFailureHandled))
                .observe(on: scheduler)
        }
    }

    fileprivate static func pullRequestChanges(
        pullRequestChanges: Signal<(PullRequestMetadata, PullRequest.Action), NoError>,
        scheduler: Scheduler
    ) -> Feedback<State, Event> {
        return Feedback(predicate: { $0.status != .starting }) { state in
            return pullRequestChanges
                .observe(on: scheduler)
                .map { metadata, action -> Event.Outcome? in
                    switch action {
                    case .opened where metadata.reference.isLabelled(with: state.integrationLabel):
                        return Event.Outcome.include(metadata.reference)
                    case .labeled where metadata.reference.isLabelled(with: state.integrationLabel) && metadata.isMerged == false:
                        return Event.Outcome.include(metadata.reference)
                    case .unlabeled where metadata.reference.isLabelled(with: state.integrationLabel) == false:
                        return Event.Outcome.exclude(metadata.reference)
                    case .closed:
                        return Event.Outcome.exclude(metadata.reference)
                    default:
                        return nil
                    }
                }
                .skipNil()
                .map(Event.pullRequestDidChange)
        }
    }
}

// MARK: - System types

extension MergeService {

    enum FailureReason: Equatable {
        case conflicts
        case mergeFailed
        case synchronizationFailed
        case checkingCommitChecksFailed
        case checksFailing
        case blocked
        case unknown
    }

    struct State: Equatable {

        enum Status: Equatable {
            case starting
            case idle
            case ready
            case integrating(PullRequestMetadata)
            case runningStatusChecks(PullRequestMetadata)
            case integrationFailed(PullRequestMetadata, FailureReason)

            var integrationMetadata: PullRequestMetadata? {
                switch self {
                case let .integrating(metadata):
                    return metadata
                default:
                    return nil
                }
            }

            var statusChecksMetadata: PullRequestMetadata? {
                switch self {
                case let .runningStatusChecks(metadata):
                    return metadata
                default:
                    return nil
                }
            }
        }

        let integrationLabel: PullRequest.Label
        let statusChecksTimeout: TimeInterval
        let pullRequests: [PullRequest]
        let status: Status

        static func initial(with integrationLabel: PullRequest.Label, statusChecksTimeout: TimeInterval) -> State {
            return State(integrationLabel: integrationLabel, statusChecksTimeout: statusChecksTimeout, pullRequests: [], status: .starting)
        }

        init(integrationLabel: PullRequest.Label, statusChecksTimeout: TimeInterval, pullRequests: [PullRequest], status: Status) {
            self.integrationLabel = integrationLabel
            self.statusChecksTimeout = statusChecksTimeout
            self.pullRequests = pullRequests
            self.status = status
        }

        func with(status: Status) -> State {
            return State(integrationLabel: integrationLabel, statusChecksTimeout: statusChecksTimeout, pullRequests: pullRequests, status: status)
        }

        func include(pullRequests pullRequestsToInclude: [PullRequest]) -> State {
            return State(
                integrationLabel: integrationLabel,
                statusChecksTimeout: statusChecksTimeout,
                pullRequests: pullRequests +
                    pullRequestsToInclude
                        .filter { [enqueued = self.pullRequests.map { $0.number }] pullRequest in
                            enqueued.contains(pullRequest.number) == false
                },
                status: status
            )
        }

        func exclude(pullRequest: PullRequest) -> State {
            return State(
                integrationLabel: integrationLabel,
                statusChecksTimeout: statusChecksTimeout,
                pullRequests: pullRequests.filter { $0.number != pullRequest.number },
                status: status
            )
        }
    }

    enum Event {
        case noMorePullRequests
        case pullRequestsLoaded([PullRequest])
        case pullRequestDidChange(Outcome)
        case statusChecksDidComplete(StatusChecksResult)
        case integrate(PullRequestMetadata)
        case retryIntegration(PullRequestMetadata)
        case integrationDidChangeStatus(IntegrationStatus, PullRequestMetadata)
        case integrationFailureHandled

        enum Outcome {
            case include(PullRequest)
            case exclude(PullRequest)
        }

        enum StatusChecksResult {
            case failed(PullRequestMetadata)
            case passed(PullRequestMetadata)
        }

        enum IntegrationStatus {
            case updating
            case done
            case failed(FailureReason)
        }
    }
}

// MARK: - Reducers

extension MergeService.State {

    fileprivate typealias Event = MergeService.Event

    fileprivate func reduceIdle(with event: Event) -> MergeService.State? {
        switch event {
        case let .pullRequestDidChange(.include(pullRequest)):
            return self.with(status: .ready).include(pullRequests: [pullRequest])
        default:
            return nil
        }
    }

    fileprivate func reduceStarting(with event: Event) -> MergeService.State? {
        switch event {
        case let .pullRequestsLoaded(pullRequests) where pullRequests.isEmpty == true:
            return self.with(status: .idle)
        case let .pullRequestsLoaded(pullRequests) where pullRequests.isEmpty == false:
            return self.with(status: .ready).include(pullRequests: pullRequests)
        default:
            return nil
        }
    }

    fileprivate func reduceReady(with event: Event) -> MergeService.State? {
        switch event {
        case .noMorePullRequests:
            return self.with(status: .idle)
        case let .integrate(metadata):
            return self.with(status: .integrating(metadata)).exclude(pullRequest: metadata.reference)
        default:
            return nil
        }
    }

    fileprivate func reduceIntegrating(with metadata: PullRequestMetadata, event: Event) -> MergeService.State? {
        switch event {
        case .integrationDidChangeStatus(.done, _):
            return self.with(status: .ready)
        case let .integrationDidChangeStatus(.failed(reason), metadata):
            return self.with(status: .integrationFailed(metadata, reason))
        case let .integrationDidChangeStatus(.updating, metadata):
            return self.with(status: .runningStatusChecks(metadata))
        case let .pullRequestDidChange(.exclude(pullRequestExcluded)) where metadata.reference.number == pullRequestExcluded.number:
            return self.with(status: .ready)
        case let .retryIntegration(metadata):
            return self.with(status: .integrating(metadata))
        default:
            return nil
        }
    }

    fileprivate func reduceRunningStatusChecks(with metadata: PullRequestMetadata, event: Event) -> MergeService.State? {
        switch event {
        case let .statusChecksDidComplete(.passed(pullRequest)):
            return self.with(status: .integrating(pullRequest))
        case let .statusChecksDidComplete(.failed(pullRequest)):
            return self.with(status: .integrationFailed(pullRequest, .checksFailing))
        case let .pullRequestDidChange(.exclude(pullRequestExcluded)) where metadata.reference.number == pullRequestExcluded.number:
            return self.with(status: .ready)
        default:
            return nil
        }
    }

    fileprivate func reduceIntegrationFailed(with event: Event) -> MergeService.State? {
        switch event {
        case .integrationFailureHandled:
            return self.with(status: .ready)
        default:
            return nil
        }
    }

    fileprivate func reduceDefault(with event: Event) -> MergeService.State {
        switch event {
        case let .pullRequestDidChange(.include(pullRequest)):
            return self.with(status: status).include(pullRequests: [pullRequest])
        case let .pullRequestDidChange(.exclude(pullRequest)):
            return self.with(status: status).exclude(pullRequest: pullRequest)
        default:
            return self
        }
    }
}

// MARK: - Helpers

private extension PullRequest {

    func isLabelled(with label: PullRequest.Label) -> Bool {
        return labels.contains(label)
    }
}

extension MergeService.State: CustomDebugStringConvertible {

    var debugDescription: String {
        return "State(\(status), pullRequests: \(pullRequests))"
    }
}

extension SignalProducer {

    static func value(_ value: Value) -> SignalProducer<Value, Error> {
        return SignalProducer(value: value)
    }

    static func error(_ error: Error) -> SignalProducer<Value, Error> {
        return SignalProducer(error: error)
    }
}

extension Int {
    public var minutes: TimeInterval {
        return Double(self) * 60
    }
}
