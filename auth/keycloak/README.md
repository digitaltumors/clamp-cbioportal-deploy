# Local Keycloak fixture

This fixture exists only to test cBioPortal SAML authentication locally. It is rendered from `realm-template.json` into the ignored `runtime/keycloak-realm.json` file by `configure-auth.sh --local`.

It uses Keycloak development mode, HTTP, a generated administrator password, and a generated test-user password. Do not deploy this overlay in production. Production must use HTTPS, an approved managed identity provider, externally managed secrets, and reviewed claim mappings.

```bash
./scripts/configure-auth.sh --local
./scripts/up.sh
```

The script prints URLs and the test username but intentionally does not print passwords. Read the ignored `.env` file when local manual testing requires them.
