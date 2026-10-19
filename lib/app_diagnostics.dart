import 'dart:io';

/// Retain context for failures handled by the UI or a recoverable background job.
void reportAppError(String operation, Object error, StackTrace stackTrace) {
  stderr.writeln('Miaosic $operation failed: $error\n$stackTrace');
}
