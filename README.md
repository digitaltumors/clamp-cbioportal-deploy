# CLAMP cBioPortal deployment

This repository builds and operates a local cBioPortal deployment containing the `clamp_2026` hg38 study and the custom CLAMP wrapper website. nginx serves the website and cBioPortal from one origin at `http://localhost:8088` by default.

## Requirements

- Docker Engine or Docker Desktop with Compose v2
- Bash, curl, Python 3, and either `sha256sum` (Linux) or `shasum` (macOS)
- at least 10 GiB of free disk space
- enough Docker memory for cBioPortal and the importer (8–12 GiB recommended during import)

This initial deployment intentionally pins cBioPortal 6.4.1 and uses its compatible MySQL schema. Do not replace it with a locally built v7 image; v7 requires a planned ClickHouse migration and fresh data import.

The checked-in `clamp_2026` study is a small, wholly synthetic fixture suitable for publishing with the deployment code. It preserves the same cBioPortal study layout and data types without distributing the private CLAMP dataset. Replace it with reviewed private data only in a deployment-specific working copy.

## First installation

```bash
./scripts/configure.sh --generate-secrets
# Review .env, especially versions, memory, port, and credentials.
./scripts/bootstrap.sh
```

Open <http://localhost:8088/test/>. Bootstrap builds the three CLAMP images, starts the databases and services, validates/imports the study exactly once, and runs smoke tests.

The initial deployment runs without authentication and is intended for a private local environment. Configure supported authentication before exposing it to a network.

## Local authentication

The repository includes a tested local SAML fixture using Keycloak 26.2.4. It protects cBioPortal, gives the generated test user access to all local studies, and enables user-associated sessions through the existing session-service and MongoDB containers.

After the first installation and study import, enable it with:

```bash
./scripts/configure-auth.sh --local
./scripts/up.sh
./scripts/smoke-test.sh
```

Open <http://localhost:8088/test/> and select **Sign in** in the cBioPortal tab. Authentication opens in a separate window because the identity-provider page cannot run inside the embedded frame. Use the generated test credentials stored in the ignored, mode-0600 `.env` file; after successful login, the window closes and the portal loads in the tab. The wrapper website remains public. `make configure-auth`, `make up`, and `make test-auth` provide the equivalent workflow.

The local realm grants its test user the cBioPortal `ALL` client role. cBioPortal 6.4.1 activates study-level permission checks whenever SAML is enabled, even when `authorization=false`; a SAML `Role` value must therefore match a study identifier/group or be `ALL`. Replace the broad local role with institution-approved study roles before production use.

`SAML_IDP_ORIGIN` must be the browser-visible origin of the identity provider, without a trailing path. cBioPortal allows that specific origin so the browser's cross-origin SAML assertion POST can reach the assertion-consumer endpoint. The HTTP localhost fixture also sets `SAML_ALLOW_NULL_ORIGIN=true` because browsers can assign an opaque `null` origin to its form navigation. Do not enable that exception in production: use the institutional HTTPS IdP origin and set `SAML_ALLOW_NULL_ORIGIN=false`.

The included Keycloak uses `start-dev`, an embedded database, HTTP, generated passwords, and a generated self-signed service-provider key. It is a local test fixture, not a production identity provider. Production must use HTTPS, managed secrets and certificates, durable IdP infrastructure, reviewed SAML claims, restricted roles, and the real public callback URL. See [authentication.md](authentication.md) and [auth/README.md](auth/README.md).

If the local Keycloak data volume is deliberately recreated, its IdP signing certificate changes. Refresh and reload the trusted metadata afterward:

```bash
./scripts/fetch-idp-metadata.sh
docker compose --env-file .env -f compose.yaml -f compose.auth.yaml restart cbioportal
```

### Docker Desktop and WSL bind-mount recovery

Generated configuration files are updated without replacing their filesystem inode so Docker Desktop can retain file bind mounts across container restarts. If a container was created by an older release, or the repository was moved while containers were running, Docker may report an OCI mount error referencing `docker-desktop-bind-mounts` and `application.properties`. After updating the repository, recreate the containers once; named database volumes are preserved:

```bash
./scripts/down.sh
./scripts/up.sh
./scripts/smoke-test.sh
```

## Normal operation

```bash
./scripts/up.sh
./scripts/status.sh
./scripts/smoke-test.sh
./scripts/down.sh       # preserves all database volumes
```

The scripts are the supported operator interface. Equivalent Make targets are available (`make up`, `make status`, and so on). The production Compose file publishes only nginx. `compose.dev.yaml` may be added explicitly when direct MySQL or cBioPortal access is required for local debugging.

## Updating the study

Replace the reviewed files under `studies/clamp_2026`, then run:

```bash
./scripts/build.sh
./scripts/validate-study.sh
./scripts/backup.sh
./scripts/import-study.sh --force
./scripts/smoke-test.sh
```

The study-loader image is labeled with a deterministic hash of every study file. Normal startup never imports data. An existing study can only be overwritten with the explicit `--force` flag. Validation and import reports, along with the last successful import record, are written to ignored files under `reports/`.

When SAML is enabled, cBioPortal protects the `/api/info` endpoint used for portal-dependent validator lookups. The loader therefore uses the official validator/importer `--no_portal_checks` mode for authenticated deployments. File-format, metadata, case-list, clinical-data, and mutation-data validation still run; the output explicitly lists the skipped portal-dependent cancer-type, gene, gene-set, and gene-panel checks. Run validation in an equivalent unauthenticated, isolated environment if those four installation-dependent checks are required.

The checked-in synthetic study has six clinical samples. Every mutation sample identifier exists in the clinical file, and the sequenced case list contains the same six identifiers.

## Backups and restore

Create a timestamped logical backup:

```bash
./scripts/backup.sh
```

Backups are written beneath `backups/` with MySQL, MongoDB, version metadata, and checksums. Copy them to durable storage; the directory is ignored by Git.

Restore is intentionally guarded and overwrites current database contents:

```bash
./scripts/restore.sh --backup backups/YYYYMMDDTHHMMSSZ
```

The restore script validates checksums, asks for confirmation, restores both databases, restarts the stack, and runs smoke tests. Use `--yes` only in controlled automation.

## Configuration

`.env.example` is safe to commit; `.env` is ignored and mode 0600 when created by `configure.sh`. Important settings include the pinned component versions, image names, web port, MySQL credentials, and Java heap sizes. `render-config.sh` converts the checked-in placeholder template into `runtime/application.properties`; that generated secret-bearing file is ignored, mode 0600, and mounted read-only into the portal and loader containers.

The default portal configuration enables several external annotation services. Review OncoKB, Genome Nexus, CIViC, and NDEx settings if study queries must remain fully offline or external variant transmission is not permitted.

## Destructive operations

`./scripts/down.sh` preserves data. Removing volumes requires both an explicit option and confirmation:

```bash
./scripts/down.sh --volumes
```

Back up first. In CI, pass `--yes`; interactive confirmation is disabled when `CI=true`.

## Release checks

```bash
./scripts/release.sh
```

This validates Compose, lints shell when ShellCheck is installed, builds images, and runs optional Syft/Trivy checks when installed. Add `--integration` for a full bootstrap test on an empty project and `--push` only after setting `IMAGE_REGISTRY`. Image pushes never happen implicitly.

## Generated and ignored files

- `.env`: local secrets and settings
- `runtime/application.properties`: rendered runtime configuration containing database secrets
- `runtime/keycloak-realm.json`: rendered local Keycloak realm containing test credentials
- `secrets/saml/`: generated SAML keypair and downloaded IdP metadata
- `reports/`: validator/import output, SBOMs, and import marker
- `backups/`: logical database backups
- `private-data/`: local staging or recovery copies of non-public studies
- `*.log` and `*.pid`: local runtime artifacts

Use `docker compose --env-file .env -f compose.yaml logs SERVICE` for detailed service logs when a script reports a failure.
