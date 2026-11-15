#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
#
# Spikes C1 to C3: can Go link Rust into its own process without cgo? Linux x86-64 only.
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"
W="$(workdir c-nocgo-linking)"
T=x86_64-unknown-linux-musl

# build_syso FEATURES SYMBOL... prelinks the Rust static library into one .syso object.
build_syso() {
	local features="$1" args=() undef=()
	shift
	[ -n "$features" ] && args=(--features "$features")
	(cd "$W/rs" && cargo build --quiet --release --target "$T" "${args[@]}")
	for s in "$@"; do undef+=(-u "$s"); done
	ld -r -o "$W/go/rsffi_linux_amd64.syso" "${undef[@]}" "$W/rs/target/$T/release/librsffi.a"
}

cd "$W/go"
go mod init spike/syso >/dev/null 2>&1
echo "== C1: Rust static library with a thread-local, internal linker (expected to fail)"
build_syso tls rs_add rs_tls_bump
if CGO_ENABLED=0 go build -o syso_demo .; then echo "unexpected: it linked"; else echo "failed as expected"; fi

echo "== C2: TLS-free function only (expected to work)"
build_syso "" rs_add
CGO_ENABLED=0 go build -o syso_demo . && ./syso_demo && file syso_demo

echo "== C3: -linkmode=external with CGO_ENABLED=0 (expected to be refused)"
cd "$W/extlink"
go mod init spike/extlink >/dev/null 2>&1
if CGO_ENABLED=0 go build -ldflags=-linkmode=external -o hello .; then echo "unexpected: it linked"; else echo "refused as expected"; fi
