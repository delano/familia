### Fixed

- **`EncryptedData.valid?` no longer echoes the candidate value into the debug log**: `valid?` runs on every assignment to an encrypted field, so the string it inspects is normally the plaintext the application just supplied. With `Familia.debug` enabled (`FAMILIA_DEBUG=1`), its success-path debug line interpolated the entire parsed value, so any plaintext that happened to be a JSON object (an API credential blob, a serialized profile) landed in the log in full, keys and values alike. The rescue path had the same shape of problem: it logged the JSON parser's exception message, which on some `json` gem versions quotes the offending input, so ordinary non-JSON plaintexts could leak through that line too. The success line now reports only the outcome and which required envelope fields are missing (never the candidate's own keys), and the rescue line logs only the exception class. Return values are unchanged. (#406)

### AI Assistance

- The fix, the log-capture regression tests, and this entry were developed with AI assistance.
