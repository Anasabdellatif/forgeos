# Operations Documentation

Operations documents define how the system is configured, deployed, monitored, recovered, and supported.

## Files

- `deployment.md`: environments, deployment prerequisites, release steps, rollback, migrations, configuration, and validation.
- `runbook.md`: routine operations, monitoring, alerts, incident response, backup, recovery, and support procedures.

## Usage

- Read this area before changing deployment, configuration, infrastructure, observability, background jobs, migrations, or recovery behavior.
- Update operations documentation with every meaningful operational change.
- Never store secrets or production credentials in this repository.

## Quality Standard

- Operational guidance must include validation evidence, rollback or recovery paths, and ownership.
- Environment-specific values should be referenced by variable name, not written as secret values.
- Production-impacting actions require explicit authorization.
