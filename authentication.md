# Authentication plan for the CLAMP cBioPortal deployment

> Implementation status: the local/test SAML path described here is implemented with Keycloak 26.2.4, authenticated cBioPortal access, and the session service. The institutional production integration remains environment-specific. Testing the pinned cBioPortal release showed that SAML mode always enables study permission evaluation; the local test user therefore receives the `ALL` client role. Production roles must be narrowed to the approved studies or groups.

## Objective

Add supported user authentication to the pinned cBioPortal 6.4.1 deployment, reconnect the existing session service so saved/shared sessions work, and retain the current same-origin nginx wrapper at `http://localhost:8088` for local development.

Authentication and authorization are separate milestones:

- **Authentication** proves who the user is and enables user-associated cBioPortal sessions.
- **Authorization** determines which authenticated users or groups can read a study. It should be enabled only after the identity-provider claims and cBioPortal authority mappings have been tested.

This plan initially authenticates cBioPortal. The custom Summary, Notes, and Methods tabs remain public unless the optional whole-site protection phase is implemented.

## Recommended approach

Use SAML 2.0 for the initial implementation because cBioPortal 6.4.1 explicitly accepts `authenticate=saml`, the repository already has an nginx reverse proxy, and cBioPortal has documented SAML support for Keycloak and institutional identity providers.

Use two identity-provider environments:

1. **Local/test:** a pinned Keycloak container and disposable test realm, delivered through a development-only Compose overlay.
2. **Production:** the institution's managed SAML identity provider, or a separately operated and hardened Keycloak instance. Do not deploy the old Keycloak 16 development example from the upstream compose repository to production.

Before selecting a Keycloak tag for the local fixture, run a compatibility spike against cBioPortal 6.4.1. The current cBioPortal documentation discusses modern Keycloak releases, while older Docker examples use Keycloak 16; neither should be assumed compatible without testing. Pin the accepted Keycloak image by version and digest.

OAuth2/OIDC remains a viable alternative if the institution requires it. If selected, use `authenticate=oauth2`, issuer discovery, a confidential client secret, and the same staged testing described below. Do not configure SAML and OAuth2 simultaneously in the first implementation.

## Target request flow

```text
Browser
  |
  v
nginx :8088
  |-- /test/* --------------------------------> custom static wrapper
  |-- /cbioportal/* --------------------------> authenticated cBioPortal
                                                     |
                                                     | SAML redirect/assertion
                                                     v
                                              Identity provider
                                                     |
                                                     v
                                              authenticated user
                                                     |
                                                     +--> session-service --> MongoDB
```

Because nginx serves the iframe and portal from one origin, cBioPortal's session cookie does not require cross-site iframe exceptions. nginx must continue forwarding the original host, port, protocol, and client address so cBioPortal generates correct SAML callback URLs.

## Scope decisions required before implementation

Record these choices in an architecture decision record or pull request:

1. Identity provider: institutional SAML IdP or managed Keycloak.
2. Public production URL, for example `https://clamp.example.edu/cbioportal`.
3. Stable SAML entity ID, for example `clamp-cbioportal`.
4. Identity attribute used as the immutable cBioPortal username. Prefer a stable institutional identifier; use email only if the IdP guarantees stability.
5. Required SAML attributes: username/subject, email, display name, and optional groups/roles.
6. Whether all authenticated users may access `clamp_2026`, or access must be group-restricted.
7. Whether only cBioPortal or the complete wrapper website must require login.
8. Logout behavior: local cBioPortal logout only or IdP single logout.
9. Session retention and backup policy for MongoDB.

## Repository changes

Extend the deployment repository with:

```text
auth/
  README.md
  saml/
    metadata.xml.example
  keycloak/
    compose.keycloak.yaml
    realm-clamp-test.json
    README.md
secrets/
  .gitkeep
scripts/
  generate-saml-keypair.sh
  fetch-idp-metadata.sh
  configure-auth.sh
  test-auth-config.sh
  test-session-service.sh
tests/
  auth/
    README.md
```

Update `.gitignore` and `.dockerignore` to exclude all generated certificates, private keys, IdP metadata containing environment details, OAuth client secrets, test-user exports, and rendered security configuration. Commit examples and schemas only.

Do not bake private keys, IdP metadata, passwords, or OAuth client secrets into any image. Mount them read-only at runtime from `secrets/`, Docker secrets, or the production secret manager.

## Configuration design

### Environment variables

Add safe variable names to `.env.example`:

```dotenv
AUTH_MODE=saml
PUBLIC_BASE_URL=http://localhost:8088
SAML_REGISTRATION_ID=cbio-saml-idp
SAML_ENTITY_ID=clamp-cbioportal
SAML_IDP_ORIGIN=http://localhost:8081
SAML_ALLOW_NULL_ORIGIN=true
SAML_IDP_METADATA_PATH=./secrets/saml/idp-metadata.xml
SAML_CERTIFICATE_PATH=./secrets/saml/local.crt
SAML_PRIVATE_KEY_PATH=./secrets/saml/local.key
SESSION_SERVICE_INSTANCE=clamp_portal
```

Production secrets must be injected outside `.env` when the deployment platform supports a secret manager. The private key must be mode `0600`; the certificate and metadata can be read-only `0644` if they contain no secrets.

Remove authentication selection from the generic JVM heap variable. `CBIOPORTAL_JAVA_OPTS` should contain JVM options only. Render `authenticate` and the SAML properties into the git-ignored runtime configuration instead of maintaining conflicting defaults between `.env.example`, `compose.yaml`, and `application.properties`.

### cBioPortal properties

For SAML, render properties equivalent to:

```properties
authenticate=saml
spring.security.saml2.relyingparty.registration.cbio-saml-idp.assertingparty.metadata-uri=classpath:/idp-metadata.xml
spring.security.saml2.relyingparty.registration.cbio-saml-idp.entity-id=clamp-cbioportal
spring.security.saml2.relyingparty.registration.cbio-saml-idp.signing.credentials[0].certificate-location=classpath:/local.crt
spring.security.saml2.relyingparty.registration.cbio-saml-idp.signing.credentials[0].private-key-location=classpath:/local.key
security.cors.allowed-origins=http://localhost:8081,null
session.service.url=http://cbioportal-session:5001/api/sessions/clamp_portal/
filter_groups_by_appname=false
```

The exact SAML attribute-mapping properties must be chosen after inspecting a real assertion from the target IdP. Do not guess email, username, or group claim names.

Mount the files into the cBioPortal classpath:

```text
idp-metadata.xml -> /cbioportal-webapp/idp-metadata.xml:ro
local.crt        -> /cbioportal-webapp/local.crt:ro
local.key        -> /cbioportal-webapp/local.key:ro
```

The existing `/cbioportal-webapp` directory is already on the application classpath in this deployment.

### Session service

The session-service and MongoDB containers already exist. Re-enable them by rendering the internal URL shown above. Keep the service reachable only on the Compose network; users should access sessions through cBioPortal, not by publishing port 5001.

Use a unique, stable final path component (`clamp_portal`) because it namespaces this portal's stored sessions. Changing it later makes prior sessions appear missing.

Continue backing up MongoDB with `scripts/backup.sh`. Add an authenticated session save/load check to backup and restore acceptance testing.

### nginx and external URL handling

Retain these forwarded headers for every cBioPortal authentication endpoint:

```nginx
proxy_set_header Host $http_host;
proxy_set_header X-Forwarded-Host $http_host;
proxy_set_header X-Forwarded-Port $server_port;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```

Verify the callback and metadata URLs produced by the running cBioPortal release. For Spring Security SAML they are expected to resemble:

```text
https://clamp.example.edu/cbioportal/login/saml2/sso/cbio-saml-idp
https://clamp.example.edu/cbioportal/saml2/service-provider-metadata/cbio-saml-idp
```

Treat those as candidates until confirmed from the running 6.4.1 application. Register only the confirmed URLs with the IdP.

Production authentication must use HTTPS. Terminate TLS at nginx or a trusted ingress/load balancer, set `X-Forwarded-Proto: https`, use secure cookies, and redirect HTTP to HTTPS. Never accept SAML assertions over plain HTTP outside isolated local testing.

Health endpoints must remain usable without interactive login so Docker and orchestration checks continue to work. Verify that `/cbioportal/api/health` exposes no sensitive information.

## Local Keycloak test fixture

Create `auth/keycloak/compose.keycloak.yaml` as a development-only overlay. It should:

- use a current, tested, pinned Keycloak image and digest;
- use a dedicated persistent database or the supported Keycloak development database only for disposable local testing;
- publish Keycloak only on a local development port such as 8081;
- import a minimal realm containing one SAML client and test users;
- avoid committing real credentials;
- generate administrator and test-user passwords during configuration; and
- be clearly labeled as unsuitable for production.

Configure the test SAML client with the confirmed cBioPortal entity ID, assertion consumer URL, logout URL, and attribute mappers. Include at least two users:

- an authenticated user with the group intended to access CLAMP; and
- an authenticated user without that group for the later authorization test.

`fetch-idp-metadata.sh` should download metadata from the configured IdP, validate that it is nonempty XML containing the expected entity ID and signing certificate, write it atomically beneath `secrets/saml/`, and refuse redirects to unapproved hosts in production mode.

`generate-saml-keypair.sh` should create an RSA private key and self-signed certificate for local testing, use configurable validity, set restrictive permissions, refuse to overwrite existing keys without an explicit flag, and print the certificate fingerprint and expiration date. Production certificates should follow institutional PKI and rotation policy instead.

## Implementation phases

### Phase 1: configuration and local authentication

1. Select and pin the local Keycloak version after a compatibility test.
2. Add the development-only Keycloak overlay and test realm.
3. Add guarded scripts for generating the service-provider key pair and fetching IdP metadata.
4. Extend `render-config.sh` to validate and render authentication properties without logging secrets.
5. Add read-only SAML file mounts to cBioPortal.
6. Switch from `authenticate=false` to `authenticate=saml`.
7. Confirm unauthenticated portal pages redirect to Keycloak and a valid user returns to the original cBioPortal URL.
8. Confirm the custom wrapper still loads and the iframe completes the redirect flow.

### Phase 2: reconnect and test sessions

1. Restore `session.service.url` with the stable `clamp_portal` namespace.
2. Log in and create a saved query/session.
3. Refresh and reopen it through its generated URL.
4. Log out and log back in; verify user-associated sessions remain available.
5. Restart cBioPortal, session-service, and MongoDB independently and verify persistence.
6. Back up and restore MongoDB in an isolated Compose project and repeat the session check.

### Phase 3: production IdP and HTTPS

1. Obtain production entity ID, metadata, attribute contract, callback approval, and certificate requirements from the IdP administrators.
2. Configure the production HTTPS hostname and forwarded-header behavior.
3. Store keys and client secrets in the deployment platform's secret manager.
4. Test metadata/signing-certificate rotation in staging.
5. Run login, logout, expired assertion, clock-skew, disabled-user, and IdP-outage scenarios.
6. Review logs to ensure assertions, cookies, access tokens, and secrets are never logged.
7. Perform a security review before public exposure.

### Phase 4: authorization, if required

Begin only after authentication is stable.

1. Define the group/role that grants access to `clamp_2026`.
2. Map the IdP group/role claim into cBioPortal authorities.
3. Configure the study's groups/authority records using supported cBioPortal tooling.
4. Decide whether the study should belong to an always-visible public group; for private CLAMP data it should not.
5. Enable authorization and method authorization in staging.
6. Prove that the allowed user can query and download the study.
7. Prove that the denied user cannot discover study metadata, query APIs, download data, or retrieve saved sessions belonging to another user.
8. Repeat direct API tests so nginx/UI hiding is never mistaken for backend authorization.

### Phase 5: optional whole-wrapper protection

cBioPortal authentication does not automatically protect `/test/` or its Summary, Notes, and Methods content. If those tabs contain private information, add an authentication gateway such as an OIDC-aware reverse-proxy sidecar in front of all nginx routes, using the same IdP.

Avoid implementing independent credentials in frontend JavaScript. The browser must never receive an OAuth client secret. Test single sign-on between the wrapper gateway and cBioPortal to avoid two login prompts.

## Script changes

Add the following behavior to the operator scripts:

- `prerequisites.sh`: require authentication files when `AUTH_MODE` is not `false`; validate permissions and certificate expiration.
- `render-config.sh`: render only an allowlist of authentication properties, validate required variables, and never print secret values.
- `up.sh`: check IdP reachability and report a specific authentication dependency failure.
- `status.sh`: show the authentication mode, IdP host, certificate fingerprint/expiration, and session-service health without displaying secrets.
- `smoke-test.sh`: retain the unauthenticated health/data checks appropriate to the chosen authorization policy, then invoke an auth-aware test suite.
- `backup.sh`: retain MongoDB and record the session namespace and authentication mode in the manifest.
- `restore.sh`: verify saved-session recovery after restore.
- `configure-auth.sh`: create the secret directories, call key/metadata helpers, validate configuration, and refuse to weaken a production configuration to HTTP or default credentials.

Browser-driven authentication should be tested with Playwright or another real browser because SAML redirects, forms, cookies, iframe navigation, and logout cannot be validated reliably with simple `curl` calls.

## Test matrix

| Test | Expected result |
| --- | --- |
| `/healthz` and cBioPortal health | Healthy without an interactive login |
| Open `/test/` | Wrapper loads; cBioPortal iframe requests authentication |
| Valid login | Returns to the original portal URL and displays the authenticated user |
| Invalid password | IdP denies access without creating a cBioPortal session |
| Missing/invalid SAML signature | cBioPortal rejects the assertion |
| Expired assertion | Login rejected with no authenticated session |
| Logout | cBioPortal session is invalidated; IdP logout follows configured policy |
| Saved query/session | Saves, reloads, and survives container restart |
| Cross-user session access | Denied according to session-service/cBioPortal policy |
| Allowed authorization group | Can access `clamp_2026` and its APIs |
| Disallowed authorization group | Cannot access or enumerate protected study data |
| IdP unavailable | Existing behavior follows policy; new login fails clearly and safely |
| Certificate near expiry | Status/monitoring warns before outage |
| nginx iframe headers | Same-origin frame remains allowed after login |
| Backup/restore | Authentication config remains external; saved sessions are restored |

## Rollout and rollback

1. Back up MySQL and MongoDB before enabling authentication.
2. Tag the current known-good no-auth images and configuration.
3. Deploy authentication to a separate staging Compose project and hostname.
4. Run the complete test matrix with representative users and groups.
5. Schedule production IdP changes and the cBioPortal configuration change together.
6. Monitor login failures, assertion validation errors, session-service errors, and certificate expiration.
7. Roll back by restoring the previous image/configuration and `authenticate=false` only if the environment is again isolated from untrusted networks. Do not use no-auth mode as a public emergency fallback.

Authentication configuration does not require reimporting `clamp_2026`. Database and session backups provide rollback protection; the study-loader image and study hash remain unchanged.

## Acceptance criteria

Authentication is complete when:

1. No default/test credentials or private key material are committed or baked into images.
2. The production portal is HTTPS-only and produces correct external callback URLs.
3. Unauthenticated users cannot access protected cBioPortal pages or protected study APIs.
4. Valid users can log in, log out, and see a stable identity.
5. Saved/shared sessions work without the "No session service configured" message and survive restarts.
6. Authorization tests pass for both allowed and denied users if study restrictions are enabled.
7. Certificate rotation, IdP outage, backup/restore, and rollback have been rehearsed in staging.
8. Monitoring alerts before certificate expiration and on sustained login/session failures.
9. The checked-in synthetic study, mutation profile, sample lists, wrapper site, and persistence smoke tests still pass.
