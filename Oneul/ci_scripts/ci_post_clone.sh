#!/bin/sh
# Xcode Cloud 전용 — 레포에 없는 Secrets.swift를 환경변수로 생성한다.
# 워크플로 Environment Variables(Secret)에 다음 3개를 등록:
#   ONEUL_PUSH_SERVER_URL / ONEUL_PUSH_REGISTER_KEY / ONEUL_NEIS_PROXY_BASE
set -e
cat > "$CI_PRIMARY_REPOSITORY_PATH/Oneul/Oneul/Secrets.swift" <<SWIFT
import Foundation

enum Secrets {
    static let pushServerURL = "${ONEUL_PUSH_SERVER_URL}"
    static let pushRegisterKey = "${ONEUL_PUSH_REGISTER_KEY}"
    static let neisProxyBase = "${ONEUL_NEIS_PROXY_BASE}"
    static let neisBakedKey = ""
}
SWIFT
echo "Secrets.swift generated"
