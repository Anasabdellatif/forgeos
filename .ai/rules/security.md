# Security Rules

Application and operational security practice. Agent-specific threats (prompt injection,
exfiltration, fabrication, supply chain) are in `ai-safety.md`. Escalation procedure is in
`.ai/contract/safety.md`.

These rules apply to **every** task, not only to work labeled as security work.

## 1. Secrets and Sensitive Data

- Never commit, log, print, or embed credentials, tokens, private keys, or production configuration.
- Use the project's approved secret manager or environment injection. Never a source file.
- Never place sensitive values in logs, error messages, exceptions, tests, fixtures, screenshots,
  URLs, query strings, or documentation.
- Use sanitized or synthetic data for development and testing.
- Rotate any secret that was exposed, even briefly, even in a private repository.
- On discovering a committed secret: stop, do not print the value, report path and line, escalate.

## 2. Trust Boundaries

- Treat every external input as hostile: request bodies, headers, query parameters, cookies, file
  uploads, webhooks, message payloads, environment values, and third-party API responses.
- Validate at the boundary: type, format, length, range, character set, and authorization.
- Prefer allowlists over denylists. Reject what is not explicitly permitted.
- Encode output for its destination — HTML, SQL, shell, URL, JSON, LDAP, log — never generically.
- Use parameterized queries and safe APIs. Never build a query, command, or path by concatenation.
- Constrain filesystem paths to an allowed root; normalize before checking, and check after
  normalizing.
- Restrict network, filesystem, database, and command access to the minimum scope required.

## 3. Authentication and Authorization

- Authentication is not authorization. Verify both, separately, on every request.
- Enforce every permission on the trusted server-side boundary. Client-side checks are UX only.
- Deny by default. A missing rule means "no".
- Check object-level ownership, not only route-level access — the most common real-world breach.
- Prevent cross-tenant and cross-user access explicitly, and test it explicitly.
- Revalidate permissions at the point of the sensitive state change, not only at session start.
- Never trust an identifier supplied by the client to determine identity or tenancy.

## 4. Data Protection

- Classify data before handling it: public, internal, confidential, personal, regulated.
- Encrypt in transit always; encrypt at rest for confidential, personal, and regulated data.
- Collect the minimum data required, retain it for the minimum period, and delete on schedule.
- Return the minimum data required. Do not serialize an entire entity because it is convenient.
- Mask or omit personal data in logs, analytics, error reports, and support tooling.

## 5. Operational Security

- Apply least privilege to every service, role, credential, token, and CI job.
- No insecure default, debug mode, verbose error page, or open CORS policy in a deployable
  environment.
- Set explicit timeouts, payload size limits, and concurrency limits on every entry point.
- Consider rate limiting, replay protection, and resource exhaustion for any public endpoint.
- Review dependency and supply-chain risk before adding, and monitor it after.
- Preserve auditability of security-relevant events — who, what, when, from where, and the
  outcome — without logging sensitive values.

## 6. Change-Time Security Review

For any change touching auth, data, input handling, or infrastructure, answer explicitly:

- [ ] What new input does this accept, and how is it validated?
- [ ] What new data does this expose, and who is authorized to see it?
- [ ] What new permission or trust relationship does this create?
- [ ] What is the worst outcome if this component is fully compromised?
- [ ] What does this log, and could any of it be sensitive?
- [ ] Does this change a security default, and was that intentional?

## 7. Response

Stop and escalate — do not conceal, and do not work around — any suspected vulnerability, secret
exposure, data-loss risk, or authorization bypass. Procedure: `.ai/contract/safety.md` §6.
