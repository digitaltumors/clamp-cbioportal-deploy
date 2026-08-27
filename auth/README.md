# Authentication assets

This directory contains commit-safe templates for the local cBioPortal SAML fixture. Generated credentials, certificates, IdP metadata, and the rendered realm are stored under ignored `secrets/`, `runtime/`, and `.env` paths.

## Local workflow

Run from the repository root:

```bash
./scripts/configure-auth.sh --local
./scripts/up.sh
./scripts/smoke-test.sh
```

`configure-auth.sh` generates administrator and test-user passwords when they are absent, creates the service-provider keypair when absent, renders `runtime/keycloak-realm.json`, starts Keycloak, validates its metadata, and renders cBioPortal's SAML and session-service properties. Re-running it preserves existing non-empty passwords so it remains consistent with an already-imported realm.

`test-auth-config.sh` checks health, SAML initiation, metadata availability, and rendered properties. `test-auth-login.py` performs the full SAML form flow with the generated user, verifies access to `clamp_2026`, and verifies that the authenticated custom-gene-list session endpoint reaches the session service.

## Role mapping

Keycloak emits client roles in the SAML attribute named `Role`. cBioPortal converts those values into study authorities. The local test realm assigns `ALL` so the fixture continues to work when studies are replaced or added.

The browser-visible IdP origin is configured through `SAML_IDP_ORIGIN`. cBioPortal must allow that exact origin because browsers attach it to Keycloak's cross-origin SAML assertion POST. The local HTTP fixture also enables `SAML_ALLOW_NULL_ORIGIN` for browser form navigations that receive an opaque origin. Keep that exception disabled in production and configure only the trusted HTTPS identity-provider origin.

For production, remove `ALL` and map only reviewed values:

- a study identifier such as `clamp_2026`;
- a group named in study metadata; or
- another deliberately configured public-study group.

Do not assume `authorization=false` disables this check in cBioPortal 6.4.1. SAML authentication activates its method-security permission evaluator.

## Production boundary

Do not deploy `compose.auth.yaml`'s development Keycloak as an institutional IdP. Supply production IdP metadata and service-provider credentials through a secret manager, use HTTPS end to end from the user's perspective, register the exact public assertion-consumer and logout URLs, establish certificate rotation, and test allowed and denied users. The custom wrapper remains public unless nginx or an upstream access proxy is configured to protect `/test/` as a separate decision.
