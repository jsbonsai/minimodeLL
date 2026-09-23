# ADR 0002: Optional managed policy replaces local configuration

Date: 2026-09-23. Status: Accepted.

## Context

The owner explicitly wants the app and Jamf layer separate. Individual users should be able to run it, and another enterprise should not need a Jamf account. The original documents mixed user-writable JSON, defaults commands and enforced corporate policy.

## Decision

Use one versioned Codable JSON schema. Forced `PolicyJSON` in the app preference domain supplies a complete managed configuration. Otherwise use user configuration, then starter defaults. Reject invalid forced policy. Jamf distributes an ordinary app package and a separately scoped profile. No Jamf SDK, API credential or privileged daemon is required by the app.

## Alternatives and consequences

Merging managed and user allowlists risks allowing users to extend policy. Embedding company settings in source creates private forks and rebuilds for routine catalog changes. A remote configuration service may become useful later but is not needed for the initial boundary.

Users can customize standalone settings; managed environments receive a complete IT-controlled configuration. Removing the managed profile permits local settings again. Policy is captured at task start, so identity/service-side revocation remains necessary for urgent interruption of external access.

## Validation and revisit conditions

Schema tests and profile lint pass. Real Jamf forced-preference precedence and sandbox behavior remain unvalidated. Consider stricter unmanaged-state behavior only as an explicit policy requirement with tests for enrollment/removal/failure, not an accidental side effect.

## Clarification: both Jamf and Kandji (2026-09-23)

The owner explicitly requested Kandji alongside Jamf. Keep artifacts and core behavior MDM-neutral. Jamf has a possible scoped test environment and will receive the first live validation. Kandji has no available tenant and is documented as best-effort until independently tested. Provider guides describe distribution/reporting differences; no separate application fork or policy schema is introduced.
