#if !canImport(ObjectiveC)
import XCTest

extension DispatchServiceTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__DispatchServiceTests = [
        ("test_adding_new_pull_requests_during_integration", test_adding_new_pull_requests_during_integration),
        ("test_creating_new_pull_requests_to_new_target_branch_without_label", test_creating_new_pull_requests_to_new_target_branch_without_label),
        ("test_mergeservice_destroyed_if_idle_long_enough", test_mergeservice_destroyed_if_idle_long_enough),
        ("test_mergeservice_destroyed_when_idle_after_boot", test_mergeservice_destroyed_when_idle_after_boot),
        ("test_mergeservice_not_destroyed_if_not_idle_long_enough", test_mergeservice_not_destroyed_if_not_idle_long_enough),
        ("test_multiple_pull_requests_with_different_target_branches", test_multiple_pull_requests_with_different_target_branches),
        ("test_queue_description", test_queue_description),
    ]
}

extension GitHubAPITests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__GitHubAPITests = [
        ("test_delete_branch", test_delete_branch),
        ("test_fetch_commit_status", test_fetch_commit_status),
        ("test_fetch_pull_request_number", test_fetch_pull_request_number),
        ("test_fetch_pull_requests", test_fetch_pull_requests),
        ("test_fetch_required_status_checks", test_fetch_required_status_checks),
        ("test_merge_branch_up_to_date", test_merge_branch_up_to_date),
        ("test_merge_branch_with_success", test_merge_branch_with_success),
        ("test_merge_pull_request", test_merge_pull_request),
        ("test_merge_pull_request_with_conflicts", test_merge_pull_request_with_conflicts),
        ("test_publish_comment", test_publish_comment),
        ("test_remove_label", test_remove_label),
    ]
}

extension GitHubDecodingTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__GitHubDecodingTests = [
        ("test_parsing_pull_request", test_parsing_pull_request),
        ("test_parsing_pull_request_event_context", test_parsing_pull_request_event_context),
        ("test_parsing_status_event_context", test_parsing_status_event_context),
    ]
}

extension GitHubEventsTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__GitHubEventsTests = [
        ("test_handling_ping_event", test_handling_ping_event),
        ("test_handling_pull_request_event", test_handling_pull_request_event),
        ("test_handling_unknown_event", test_handling_unknown_event),
        ("test_handling_untrustworthy_payload", test_handling_untrustworthy_payload),
    ]
}

extension MergeServiceHealthcheckTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__MergeServiceHealthcheckTests = [
        ("test_healthcheck_failing", test_healthcheck_failing),
        ("test_healthcheck_passing", test_healthcheck_passing),
    ]
}

extension MergeServiceTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__MergeServiceTests = [
        ("test_adding_a_new_pull_request_while_running_an_integrating", test_adding_a_new_pull_request_while_running_an_integrating),
        ("test_changing_pull_request_priorities", test_changing_pull_request_priorities),
        ("test_closing_pull_request_during_integration", test_closing_pull_request_during_integration),
        ("test_empty_list_of_pull_requests_should_do_nothing", test_empty_list_of_pull_requests_should_do_nothing),
        ("test_excluding_pull_request_in_the_queue", test_excluding_pull_request_in_the_queue),
        ("test_multiple_pull_requests_with_integration_label_and_ready_to_merge", test_multiple_pull_requests_with_integration_label_and_ready_to_merge),
        ("test_no_pull_requests_with_integration_label", test_no_pull_requests_with_integration_label),
        ("test_pull_request_blocked_with_successful_status_no_pending_checks", test_pull_request_blocked_with_successful_status_no_pending_checks),
        ("test_pull_request_blocked_with_successful_status_pending_checks", test_pull_request_blocked_with_successful_status_pending_checks),
        ("test_pull_request_does_not_fail_prematurely_if_checks_complete_before_adding_the_following_checks", test_pull_request_does_not_fail_prematurely_if_checks_complete_before_adding_the_following_checks),
        ("test_pull_request_fails_integration_after_timeout", test_pull_request_fails_integration_after_timeout),
        ("test_pull_request_not_included_on_close", test_pull_request_not_included_on_close),
        ("test_pull_request_with_an_initial_unknown_state_with_recover", test_pull_request_with_an_initial_unknown_state_with_recover),
        ("test_pull_request_with_an_initial_unknown_state_without_recover", test_pull_request_with_an_initial_unknown_state_without_recover),
        ("test_pull_request_with_integration_label_and_behind_target_branch", test_pull_request_with_integration_label_and_behind_target_branch),
        ("test_pull_request_with_integration_label_and_conflicts", test_pull_request_with_integration_label_and_conflicts),
        ("test_pull_request_with_integration_label_and_ready_to_merge", test_pull_request_with_integration_label_and_ready_to_merge),
        ("test_pull_request_with_multiple_status_checks", test_pull_request_with_multiple_status_checks),
        ("test_pull_request_with_non_required_failed_status_checks_requiresAllStatusChecks_off", test_pull_request_with_non_required_failed_status_checks_requiresAllStatusChecks_off),
        ("test_pull_request_with_non_required_failed_status_checks_requiresAllStatusChecks_on", test_pull_request_with_non_required_failed_status_checks_requiresAllStatusChecks_on),
        ("test_pull_request_with_status_checks_failing", test_pull_request_with_status_checks_failing),
        ("test_pull_requests_receive_feedback_when_accepted", test_pull_requests_receive_feedback_when_accepted),
        ("test_removing_the_integration_label_during_integration", test_removing_the_integration_label_during_integration),
        ("test_resuming_after_labelling_a_pull_request", test_resuming_after_labelling_a_pull_request),
    ]
}

extension ResponseTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ResponseTests = [
        ("test_decoding_with_next_page_available", test_decoding_with_next_page_available),
        ("test_decoding_without_more_pages", test_decoding_without_more_pages),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DispatchServiceTests.__allTests__DispatchServiceTests),
        testCase(GitHubAPITests.__allTests__GitHubAPITests),
        testCase(GitHubDecodingTests.__allTests__GitHubDecodingTests),
        testCase(GitHubEventsTests.__allTests__GitHubEventsTests),
        testCase(MergeServiceHealthcheckTests.__allTests__MergeServiceHealthcheckTests),
        testCase(MergeServiceTests.__allTests__MergeServiceTests),
        testCase(ResponseTests.__allTests__ResponseTests),
    ]
}
#endif
