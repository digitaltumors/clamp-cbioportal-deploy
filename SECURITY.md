# Deployment security

The default deployment is a loopback-only development environment. It is safe for the checked-in synthetic study, but private data must not be published until the production checks in `scripts/prerequisites.sh` pass.

## Implemented controls

- nginx and development ports bind to loopback by default. nginx remains loopback-only; production traffic must enter through a trusted local TLS ingress. An HTTPS public URL requires SAML, an external HTTPS IdP, trusted-proxy mode, and encrypted-backup configuration.
- MongoDB 7 authorization uses separate root and least-privilege application credentials. The browser-facing web container has no database network route; MySQL and MongoDB use separate internal networks. Session containers are not started in no-auth mode.
- MySQL, MongoDB, nginx, Keycloak, cBioPortal, Java-runtime, Maven-builder, Go-builder, and Node-builder bases are version-and-manifest-digest pinned. cBioPortal maintenance-v6 and session-service source revisions are full Git commit pins. Reviewable POM patches upgrade vulnerable libraries without changing the cBioPortal 6/MySQL architecture; custom runtime layers also install available OS security updates.
- The bundled Keycloak fixture is a loopback-only local test profile. External SAML uses `configure-auth.sh --external HTTPS_METADATA_URL`, does not start Keycloak, rejects `null` origins, and requires an HTTPS IdP origin.
- Containers have explicit users where compatible, capability drops, `no-new-privileges`, read-only filesystems for stateless services, private tmpfs mounts, PID limits, and CPU/memory limits.
- Study content is mounted read-only at import time and excluded from the loader build context and image layers. Keep private studies outside this Git repository and point `STUDY_DATA_PATH` to them.
- nginx emits a complete CSP while retaining same-origin cBioPortal framing, plus HSTS when requests arrive from the trusted HTTPS ingress and standard browser security headers.
- Generated secrets use `umask 077`, unpredictable mode-0600 temporary files, and ignored final paths. Generated passwords are not passed in process arguments.
- Backups are mode 0600 under mode-0700 directories. Set `BACKUP_AGE_RECIPIENT`; private externally published deployments require it. Restore requires `BACKUP_AGE_IDENTITY`.
- `release.sh` and CI generate SPDX SBOMs and fail on HIGH or CRITICAL findings for all seven deployable images. Scanner images and GitHub Actions are immutable-reference pinned; evidence is retained under `reports/security`.

## Vulnerability remediation and gate status

The 2026-09-11 Trivy 0.74.0 scan below is the pre-source-rebuild baseline. It reduced HIGH/CRITICAL occurrences from 930 to 273 (about 71%) but still blocked release.

| Deployable image | Before | After | Remaining source |
| --- | ---: | ---: | --- |
| cBioPortal | 362 | 73 | Embedded application Java dependencies |
| Study loader | 362 | 73 | Same cBioPortal application dependencies |
| Web/nginx | 7 | 0 | None |
| Session service | 41 | 27 | Embedded application Java dependencies |
| MySQL | 58 | 0 | None |
| MongoDB | 97 | 97 | Bundled MongoDB database tools, `gosu`, and `js-yaml` |
| Local Keycloak fixture | 3 | 3 | Required Java/runtime dependencies; one has no vendor fix |

The 2026-09-23 remediation rebuild produced this current result:

| Deployable image | HIGH/CRITICAL rows | Result |
| --- | ---: | --- |
| cBioPortal | 0 | Pass |
| Study loader | 0 | Pass |
| Web/nginx | 0 | Pass |
| Session service | 0 | Pass |
| MySQL | 0 | Pass |
| MongoDB | 0 | Pass |
| Local Keycloak fixture | 5 exempted | Pass until the approved exceptions expire |

The current implementation rebuilds cBioPortal and session-service from pinned source with patched dependency versions instead of swapping loose JARs. The study loader inherits that exact cBioPortal image. MongoDB is a derived image with a rebuilt `gosu`, updated Database Tools and mongosh, and patched `js-yaml` 3.15.2. The redundant cBioPortal core archive and unused ClickHouse driver are removed. Keycloak is upgraded to 26.7.4 and overlays Netty Handler 4.1.137 and Bouncy Castle 1.85; its local H2-only fixture replaces the unused SQL Server driver implementation with an empty JAR at the Quarkus-required path.

The remaining Keycloak rows are CVE-2026-86145 and CVE-2026-89161 against both `pcre2` and `pcre2-syntax` in the Red Hat 9.8 base. Trivy reports no fixed version. The fifth row, CVE-2025-59250, is retained in Quarkus' serialized application model even though the SQL Server implementation is absent. Ticket SEC-1 temporarily exempts these exact package URLs through 2026-10-23, owned by the UCSD Ideker Lab Software Team and approved by Daniel Halmos. Exact unfiltered findings and SPDX SBOMs are retained in ignored, mode-0600 files under `reports/security`; the gate will fail automatically when the exceptions expire, stop matching, or are removed before a fixed Keycloak base is adopted.

## Existing MongoDB 4.2 installations

MongoDB does not support attaching a 4.2 data directory directly to MongoDB 7. After updating `.env` with generated `MONGO_ROOT_PASSWORD` and `MONGO_APP_PASSWORD` values, keep the old MongoDB 4.2 container and volume intact and run:

```bash
./scripts/migrate-mongo-4.2.sh
```

The script resolves the exact Compose-labeled container and volume, confirms before removal, writes a mode-0600 logical rollback archive, recreates the volume with authenticated MongoDB 7, and restores the session database. Use `--yes` only in controlled automation. Back up MySQL separately before deployment maintenance.

## Remaining production responsibilities

TLS must terminate at a trusted ingress that is the only network path to nginx. Use institution-managed SAML certificates and narrowly scoped study roles; never expose the local Keycloak fixture. Store `.env`, SAML keys, age identities, and backups in the organization’s managed secret/backup systems. Review scanner failures rather than adding permanent ignores; any exception should name the CVE, owner, expiry, and compensating control. Validate denied users, SAML replay/expiry/signatures, secure cookies, TLS redirects, restore, and incident rollback in staging.
