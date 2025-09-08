// WorkManager task name
const String kRetryTask = 'retry_forwarding_task';

// Forwarder names used throughout the codebase
const String kFwdHttp = 'HttpCallbackForwarder';
const String kFwdTg = 'TelegramBotForwarder';
const String kFwdDeployed = 'DeployedTelegramBotForwarder';

// Retry and queue constants
const int kDefaultMaxRetries = 3;
const Duration kReservationTtl = Duration(minutes: 5);
const int kMaxItemsPerRun = 10;

// Per-forwarder attempt state for retries
enum ForwarderAttemptState {
  pending,
  success,
  retriableFailure,
  nonRetriableFailure,
}

String forwarderAttemptStateToString(ForwarderAttemptState s) {
  switch (s) {
    case ForwarderAttemptState.pending:
      return 'pending';
    case ForwarderAttemptState.success:
      return 'success';
    case ForwarderAttemptState.retriableFailure:
      return 'retriable_failure';
    case ForwarderAttemptState.nonRetriableFailure:
      return 'non_retriable_failure';
  }
}

ForwarderAttemptState forwarderAttemptStateFromString(String s) {
  switch (s) {
    case 'success':
      return ForwarderAttemptState.success;
    case 'retriable_failure':
      return ForwarderAttemptState.retriableFailure;
    case 'non_retriable_failure':
      return ForwarderAttemptState.nonRetriableFailure;
    case 'pending':
    default:
      return ForwarderAttemptState.pending;
  }
}
