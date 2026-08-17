## 0.3.1

- Avatar URLs are summarized (`data:` URLs especially) and user metadata over
  16KB is replaced with a `__buoyOmitted` marker, keeping `role` so the user card
  still badges. Apps put base64 photos on `avatarUrl` and dump the whole API user
  into `metadata`; a few history entries of those exceeded the emit budget.

## 0.3.0

- Initial release: 1:1 Flutter port of `@buoy-gg/impersonate`.
- Persisted `BuoyImpersonate` override store (RN key `@buoy/impersonate/state`),
  search/history/settings modal, and the impersonate sync adapter for Buoy Desktop.
