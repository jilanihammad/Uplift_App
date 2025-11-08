/// Runtime switches for verbose logging categories.
/// Flip these flags (e.g., via a debug panel) when deep diagnostics are needed
/// without permanently spamming standard logs.
class LogChannels {
  static bool vadTrace = false;
  static bool ttsTrace = false;
  static bool recordingTrace = false;
  static bool therapyTrace = false;
}
