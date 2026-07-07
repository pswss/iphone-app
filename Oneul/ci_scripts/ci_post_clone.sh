#!/bin/sh
# Xcode Cloud 전용 — 레포에 없는 Secrets.swift를 환경변수로 생성한다.
# ASC 환경변수가 URL 특수문자를 거부해서 URL 값은 hex 인코딩으로 받는다.
# 등록할 변수(전부 Secret):
#   ONEUL_PUSH_SERVER_URL_HEX / ONEUL_PUSH_REGISTER_KEY / ONEUL_NEIS_PROXY_BASE_HEX
set -e
dec() { printf '%s' "$1" | xxd -r -p; }
cat > "$CI_PRIMARY_REPOSITORY_PATH/Oneul/Oneul/Secrets.swift" <<SWIFT
import Foundation

enum Secrets {
    static let pushServerURL = "$(dec "$ONEUL_PUSH_SERVER_URL_HEX")"
    static let pushRegisterKey = "${ONEUL_PUSH_REGISTER_KEY}"
    static let neisProxyBase = "$(dec "$ONEUL_NEIS_PROXY_BASE_HEX")"
    static let neisBakedKey = ""
}
SWIFT
echo "Secrets.swift generated"
