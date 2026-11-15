#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
#
# Spikes B1 and B2 (Plan B): cgo with a Rust static library, using the host C
# toolchain. Linux x86-64 with gcc and clang installed.
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"
W="$(workdir b-cgo)"
cp -R "$SPIKES_DIR/rust-stub-lib" "$W/rs"
(cd "$W/rs" && cargo build --quiet --release --target x86_64-unknown-linux-gnu)
mkdir -p "$W/go/lib"
cp "$W/rs/target/x86_64-unknown-linux-gnu/release/librsengine.a" "$W/go/lib/"

cd "$W/go"
go mod init spike/cgo >/dev/null 2>&1
echo "== B1: native cgo build with the host toolchain"
CGO_ENABLED=1 go build -o cgo_demo . && ./cgo_demo

echo "== B2: cgo cross-build to linux/arm64 with host clang and no sysroot (expected to fail)"
if CGO_ENABLED=1 GOOS=linux GOARCH=arm64 CC="clang --target=aarch64-linux-gnu" go build -o cgo_arm64 .; then
	echo "unexpected: it built"
else
	echo "failed as expected"
fi
