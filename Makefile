SHELL := /usr/bin/env bash

.PHONY: configure configure-auth build validate import up down status test test-auth backup release bootstrap

configure:
	./scripts/configure.sh

configure-auth:
	./scripts/configure-auth.sh --local

build:
	./scripts/build.sh

validate:
	./scripts/validate-study.sh

import:
	./scripts/import-study.sh

up:
	./scripts/up.sh

down:
	./scripts/down.sh

status:
	./scripts/status.sh

test:
	./scripts/smoke-test.sh

test-auth:
	./scripts/test-auth-config.sh
	./scripts/test-auth-login.py .

backup:
	./scripts/backup.sh

release:
	./scripts/release.sh

bootstrap:
	./scripts/bootstrap.sh
