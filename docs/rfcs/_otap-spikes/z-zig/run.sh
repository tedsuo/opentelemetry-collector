#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
#
# Spikes Z1 to Z4 (Plan Z): one cgo + Rust program cross-built with Zig as the
# C compiler and linker for linux/amd64, linux/arm64, windows/amd64 and darwin/arm64.
# macOS links against the stub .tbd files in macos-stubs instead of Apple's SDK.
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"
W="$(workdir z-zig)"
cp -R "$SPIKES_DIR/rust-stub-lib" "$W/rs"
ZB="$W/zigbin"
make_zig_wrappers "$ZB" x86_64-linux-musl aarch64-linux-musl x86_64-windows-gnu aarch64-macos

# The Rust static libraries need no linker, so cargo builds them without Zig.
for pair in linux_amd64:x86_64-unknown-linux-musl linux_arm64:aarch64-unknown-linux-musl \
	windows_amd64:x86_64-pc-windows-gnu darwin_arm64:aarch64-apple-darwin; do
	IFS=: read -r platform target <<<"$pair"
	(cd "$W/rs" && cargo build --quiet --release --target "$target")
	mkdir -p "$W/go/lib/$platform"
	cp "$W/rs/target/$target/release/librsengine.a" "$W/go/lib/$platform/"
done

cd "$W/go"
go mod init spike/z >/dev/null 2>&1
# zbuild GOOS GOARCH ZIG_TARGET OUTPUT EXTLDFLAGS
zbuild() {
	CGO_ENABLED=1 GOOS="$1" GOARCH="$2" CC="$ZB/zcc-$3" CXX="$ZB/zcxx-$3" \
		go build -trimpath -tags netgo,osusergo -ldflags "-s -w -linkmode external $5" -o "$4" .
	file "$4"
}
zbuild linux amd64 x86_64-linux-musl z_linux_amd64 "-extldflags -static"
zbuild linux arm64 aarch64-linux-musl z_linux_arm64 "-extldflags -static"
zbuild windows amd64 x86_64-windows-gnu z_windows_amd64.exe ""
zbuild darwin arm64 aarch64-macos z_darwin_arm64 "-extldflags '-F$W/macos-stubs -L$W/macos-stubs'"
run_native z_linux_
