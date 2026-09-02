### Fixed

- **Deserialization failure logs no longer carry the stored value**: when `deserialize_value` falls back to returning a raw string (a legacy plain string or corrupted JSON), `log_deserialization_issue` truncated the value to 50 characters in the structured `value_preview` field but interpolated the full `val.inspect` into the message itself. That message is logged at ERROR (ungated) and also wrapped in the `StandardError` handed to `Familia::Instrumentation.notify_error`, so on every load of an affected record the complete value, which can include raw ciphertext migrated from older encryption schemes, reached the log and any error-reporting sink. The message now carries only the classification, the `Class#field` context and the dbkey, so the ERROR line and the `notify_error` payload contain no bytes of the value at default settings. A new `value_length` (byte size) is always reported in both the log context and the `notify_error` context; the bounded `value_preview` is only added to the log context when `Familia.debug?` is on, and is never sent to `notify_error`. The classification is also computed once per call instead of twice. The return value and control flow of `deserialize_value` are unchanged. (#407)

### AI Assistance

- The redaction change, the debug-gated preview, and the accompanying log and instrumentation tests were developed with AI assistance.
