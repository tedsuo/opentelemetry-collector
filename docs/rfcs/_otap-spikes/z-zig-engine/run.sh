#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
#
# Spikes Z5 and Z6 (Plan Z): the real OTAP Dataflow Engine as a static library
# inside a Go process, with its C crates (ring, jemalloc, zstd) compiled by Zig.
# Needs OTEL_ARROW_DIR: an otel-arrow checkout (tested at 8312b7a) with
# otel-arrow-musl.patch applied. Each target takes about 10 minutes on 4 cores.
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"
: "${OTEL_ARROW_DIR:?set OTEL_ARROW_DIR to an otel-arrow checkout}"
PATCH="$SPIKES_DIR/z-zig-engine/otel-arrow-musl.patch"
if ! git -C "$OTEL_ARROW_DIR" apply --reverse --check "$PATCH" 2>/dev/null; then
	echo "The engine needs the musl fix first: git -C \"$OTEL_ARROW_DIR\" apply \"$PATCH\"" >&2
	exit 1
fi

W="$(workdir z-zig-engine)"
DFE="$(cd "$OTEL_ARROW_DIR/rust/otap-dataflow" && pwd)"
sed "s#@OTEL_ARROW_DFE@#$DFE#g" "$W/host-ffi/Cargo.toml.in" >"$W/host-ffi/Cargo.toml"
ZB="$W/zigbin"
make_zig_wrappers "$ZB" x86_64-linux-musl aarch64-linux-musl
TARGET_DIR="${CARGO_TARGET_DIR:-$W/host-ffi/target}"

cd "$W/go"
go mod init spike/engine >/dev/null 2>&1
# ARCHES picks the targets to build, for example ARCHES=amd64.
for arch in ${ARCHES:-amd64 arm64}; do
	case "$arch" in
	amd64) target=x86_64-unknown-linux-musl zig_target=x86_64-linux-musl ;;
	arm64) target=aarch64-unknown-linux-musl zig_target=aarch64-linux-musl ;;
	*) echo "unsupported arch: $arch" >&2 && exit 1 ;;
	esac
	tu="${target//-/_}"
	(cd "$W/host-ffi" && env "CC_$tu=$ZB/zcc-$zig_target" "CXX_$tu=$ZB/zcxx-$zig_target" "AR_$tu=$ZB/zar" \
		cargo build --release --target "$target")
	mkdir -p "lib/linux_$arch"
	ln -sf "$TARGET_DIR/$target/release/libotap_host_ffi.a" "lib/linux_$arch/libotap_host_ffi.a"
	CGO_ENABLED=1 GOOS=linux GOARCH="$arch" CC="$ZB/zcc-$zig_target" CXX="$ZB/zcxx-$zig_target" \
		go build -trimpath -tags netgo,osusergo -ldflags "-s -w -linkmode external -extldflags -static" -o "otelcol-otap-$arch" .
	file "otelcol-otap-$arch"
done
run_native otelcol-otap-
