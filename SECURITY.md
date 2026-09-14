# Deployment security

The default deployment is a loopback-only development environment. It is safe for the checked-in synthetic study, but private data must not be published until the production checks in `scripts/prerequisites.sh` pass.

## Implemented controls

- nginx and development ports bind to loopback by default. nginx remains loopback-only; production traffic must enter through a trusted local TLS ingress. An HTTPS public URL requires SAML, an external HTTPS IdP, trusted-proxy mode, and encrypted-backup configuration.
- MongoDB 7 authorization uses separate root and least-privilege application credentials. The browser-facing web container has no database network route; MySQL and MongoDB use separate internal networks. Session containers are not started in no-auth mode.
- MySQL, MongoDB, nginx, session-service, Keycloak, cBioPortal, Java-runtime, and Go-builder bases are version-and-manifest-digest pinned. Custom runtime layers install available OS security updates. The cBioPortal 6.4.5 pin is retained because upgrading to v7 also requires the planned ClickHouse/schema migration.
- The bundled Keycloak fixture is a loopback-only local test profile. External SAML uses `configure-auth.sh --external HTTPS_METADATA_URL`, does not start Keycloak, rejects `null` origins, and requires an HTTPS IdP origin.
- Containers have explicit users where compatible, capability drops, `no-new-privileges`, read-only filesystems for stateless services, private tmpfs mounts, PID limits, and CPU/memory limits.
- Study content is mounted read-only at import time and excluded from the loader build context and image layers. Keep private studies outside this Git repository and point `STUDY_DATA_PATH` to them.
- nginx emits a complete CSP while retaining same-origin cBioPortal framing, plus HSTS when requests arrive from the trusted HTTPS ingress and standard browser security headers.
- Generated secrets use `umask 077`, unpredictable mode-0600 temporary files, and ignored final paths. Generated passwords are not passed in process arguments.
- Backups are mode 0600 under mode-0700 directories. Set `BACKUP_AGE_RECIPIENT`; private externally published deployments require it. Restore requires `BACKUP_AGE_IDENTITY`.
- `release.sh` and CI generate SPDX SBOMs and fail on HIGH or CRITICAL findings for all seven deployable images. Scanner images and GitHub Actions are immutable-reference pinned; evidence is retained under `reports/security`.

## Current vulnerability gate status

The 2026-09-11 Trivy 0.74.0 rescan completed against the exact rebuilt images and still **blocked release**. Remediation reduced HIGH/CRITICAL occurrences from 930 to 273 (about 71%) while preserving the tested cBioPortal 6/MySQL architecture.

| Deployable image | Before | After | Remaining source |
| --- | ---: | ---: | --- |
| cBioPortal | 362 | 73 | Embedded application Java dependencies |
| Study loader | 362 | 73 | Same cBioPortal application dependencies |
| Web/nginx | 7 | 0 | None |
| Session service | 41 | 27 | Embedded application Java dependencies |
| MySQL | 58 | 0 | None |
| MongoDB | 97 | 97 | Bundled MongoDB database tools, `gosu`, and `js-yaml` |
| Local Keycloak fixture | 3 | 3 | Required Java/runtime dependencies; one has no vendor fix |

The cBioPortal and session-service dependencies cannot be safely replaced as loose JARs in prebuilt applications; they require tested upstream application rebuilds. MongoDB's affected database tools are required by backup, restore, and migration scripts. Keycloak's JDBC driver is referenced by its generated classpath even when the local fixture uses H2, so deleting it prevents startup. Exact findings and SPDX SBOMs are retained in ignored, mode-0600 files under `reports/security`. CI and `release.sh` intentionally remain red until compatible upstream releases eliminate the findings or narrowly reviewed, expiring CVE exceptions are approved. Do not bypass the gate or publish these images as an approved production release based only on this reduction.

## Existing MongoDB 4.2 installations

MongoDB does not support attaching a 4.2 data directory directly to MongoDB 7. After updating `.env` with generated `MONGO_ROOT_PASSWORD` and `MONGO_APP_PASSWORD` values, keep the old MongoDB 4.2 container and volume intact and run:

```bash
./scripts/migrate-mongo-4.2.sh
```

The script resolves the exact Compose-labeled container and volume, confirms before removal, writes a mode-0600 logical rollback archive, recreates the volume with authenticated MongoDB 7, and restores the session database. Use `--yes` only in controlled automation. Back up MySQL separately before deployment maintenance.

## Remaining production responsibilities

TLS must terminate at a trusted ingress that is the only network path to nginx. Use institution-managed SAML certificates and narrowly scoped study roles; never expose the local Keycloak fixture. Store `.env`, SAML keys, age identities, and backups in the organization’s managed secret/backup systems. Review scanner failures rather than adding permanent ignores; any exception should name the CVE, owner, expiry, and compensating control. Validate denied users, SAML replay/expiry/signatures, secure cookies, TLS redirects, restore, and incident rollback in staging.
