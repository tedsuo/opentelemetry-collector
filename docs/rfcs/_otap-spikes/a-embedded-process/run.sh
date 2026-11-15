#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
#
# Spike A (Plan A): a std-only engine stub built as static musl executables with
# Rust's bundled rust-lld, so no C toolchain is needed. A CGO_ENABLED=0 Go host
# embeds it, launches it from memfd and coordinates startup and shutdown.
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"
W="$(workdir a-embedded-process)"

mkdir -p "$W/host/bin"
for pair in amd64:x86_64-unknown-linux-musl arm64:aarch64-unknown-linux-musl; do
	IFS=: read -r arch target <<<"$pair"
	(cd "$W/engine" && RUSTFLAGS="-C linker=rust-lld -C link-self-contained=yes -C target-feature=+crt-static" \
		cargo build --quiet --release --target "$target")
	cp "$W/engine/target/$target/release/engine" "$W/host/bin/engine_linux_$arch"
done

cd "$W/host"
go mod init spike/otaphost >/dev/null 2>&1
go get golang.org/x/sys@v0.50.0 >/dev/null 2>&1
for arch in amd64 arm64; do
	CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -trimpath -ldflags="-s -w" -o "otelcol-otap-$arch" .
	file "otelcol-otap-$arch"
done
run_native otelcol-otap-
