#!/usr/bin/env python3
"""Exercise the local Keycloak SAML login without exposing credentials in process arguments."""

from __future__ import annotations

import http.cookiejar
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser


class FormParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.forms: list[dict[str, object]] = []
        self.current: dict[str, object] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "form":
            self.current = {"action": values.get("action", ""), "inputs": {}}
            self.forms.append(self.current)
        elif tag == "input" and self.current is not None:
            name = values.get("name")
            if name:
                inputs = self.current["inputs"]
                assert isinstance(inputs, dict)
                inputs[name] = values.get("value", "")


class LocalhostCookiePolicy(http.cookiejar.DefaultCookiePolicy):
    """Match browser handling of Secure cookies on the localhost secure context."""

    def return_ok_secure(
        self, cookie: http.cookiejar.Cookie, request: urllib.request.Request
    ) -> bool:
        host = urllib.parse.urlparse(request.full_url).hostname
        if cookie.secure and host in {"localhost", "127.0.0.1", "::1"}:
            return True
        return super().return_ok_secure(cookie, request)


def parse_env(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        if raw and not raw.lstrip().startswith("#") and "=" in raw:
            key, value = raw.split("=", 1)
            values[key] = value
    return values


def parse_forms(body: bytes) -> list[dict[str, object]]:
    parser = FormParser()
    parser.feed(body.decode("utf-8", errors="replace"))
    return parser.forms


def post_form(
    opener: urllib.request.OpenerDirector,
    url: str,
    values: dict[str, str],
    origin: str | None = None,
):
    data = urllib.parse.urlencode(values).encode()
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    if origin:
        headers["Origin"] = origin
    return opener.open(
        urllib.request.Request(
            url,
            data=data,
            headers=headers,
        ),
        timeout=30,
    )


def select_form(forms: list[dict[str, object]], required_field: str) -> dict[str, object]:
    for form in forms:
        inputs = form["inputs"]
        assert isinstance(inputs, dict)
        if required_field in inputs:
            return form
    raise RuntimeError(f"No HTML form containing {required_field!r}")


def read_stage(stage: str, operation) -> bytes:
    try:
        return operation().read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(
            f"{stage} returned HTTP {exc.code} from {exc.url}"
        ) from exc


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: test-auth-login.py REPOSITORY_ROOT")
    root = pathlib.Path(sys.argv[1]).resolve()
    env = parse_env(root / ".env")
    username = env.get("AUTH_TEST_USERNAME", "")
    password = env.get("AUTH_TEST_PASSWORD", "")
    if not username or not password:
        raise SystemExit("Local auth test credentials are not configured")
    base = env.get("PUBLIC_BASE_URL", "http://localhost:8088").rstrip("/")
    registration = env.get("SAML_REGISTRATION_ID", "cbio-saml-idp")

    # Keycloak's SAML cookies are deliberately Secure because assertions cross
    # sites. Browsers consider localhost a secure context; CookieJar does not.
    jar = http.cookiejar.CookieJar(policy=LocalhostCookiePolicy())
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    initiation_url = f"{base}/cbioportal/saml2/authenticate/{registration}"
    initiation = read_stage(
        "cBioPortal SAML initiation",
        lambda: opener.open(initiation_url, timeout=30),
    )
    saml_form = select_form(parse_forms(initiation), "SAMLRequest")
    saml_inputs = saml_form["inputs"]
    assert isinstance(saml_inputs, dict)
    idp_response = read_stage(
        "Keycloak authentication-session creation",
        lambda: post_form(
            opener, str(saml_form["action"]), saml_inputs, origin=base
        ),
    )

    login_form = select_form(parse_forms(idp_response), "username")
    login_inputs = login_form["inputs"]
    assert isinstance(login_inputs, dict)
    login_inputs.update({"username": username, "password": password})
    login_url = urllib.parse.urljoin(base, str(login_form["action"]))
    assertion_page = read_stage(
        "Keycloak credential submission",
        lambda: post_form(opener, login_url, login_inputs),
    )

    assertion_form = select_form(parse_forms(assertion_page), "SAMLResponse")
    assertion_inputs = assertion_form["inputs"]
    assert isinstance(assertion_inputs, dict)
    assertion_url = urllib.parse.urljoin(base, str(assertion_form["action"]))
    read_stage(
        "cBioPortal SAML assertion consumer",
        lambda: post_form(
            opener,
            assertion_url,
            assertion_inputs,
            origin=(
                "null"
                if env.get("SAML_ALLOW_NULL_ORIGIN", "false").lower() == "true"
                else env.get("SAML_IDP_ORIGIN", "http://localhost:8081")
            ),
        ),
    )

    study_body = read_stage(
        "authenticated study API",
        lambda: opener.open(
            f"{base}/cbioportal/api/studies/clamp_2026", timeout=30
        ),
    )
    study = json.loads(study_body)
    if study.get("studyId") != "clamp_2026":
        raise RuntimeError("Authenticated study API did not return clamp_2026")

    expected = json.loads((root / "tests" / "expected-study.json").read_text())
    api_checks = (
        (
            "authenticated sample API",
            "studies/clamp_2026/samples?projection=ID",
            lambda payload: len(payload) == expected["sample_count"],
            f'expected {expected["sample_count"]} samples',
        ),
        (
            "authenticated molecular-profile API",
            "studies/clamp_2026/molecular-profiles",
            lambda payload: expected["molecular_profile_id"]
            in {item.get("molecularProfileId") for item in payload},
            f'missing molecular profile {expected["molecular_profile_id"]}',
        ),
        (
            "authenticated sample-list API",
            "studies/clamp_2026/sample-lists",
            lambda payload: expected["case_list_id"]
            in {item.get("sampleListId") for item in payload},
            f'missing sample list {expected["case_list_id"]}',
        ),
    )
    for stage, path, predicate, failure in api_checks:
        body = read_stage(
            stage,
            lambda path=path: opener.open(
                f"{base}/cbioportal/api/{path}", timeout=30
            ),
        )
        payload = json.loads(body)
        if not predicate(payload):
            raise RuntimeError(f"{stage} failed: {failure}")

    session_body = read_stage(
        "authenticated session service",
        lambda: opener.open(
            f"{base}/cbioportal/api/session/custom_gene_list", timeout=30
        ),
    )
    saved_gene_lists = json.loads(session_body)
    if not isinstance(saved_gene_lists, list):
        raise RuntimeError("Session service did not return a custom-gene-list array")

    print(
        "Authenticated SAML login, six-sample study APIs, and session service tests passed"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, urllib.error.HTTPError, urllib.error.URLError) as exc:
        print(f"Authentication login test failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
