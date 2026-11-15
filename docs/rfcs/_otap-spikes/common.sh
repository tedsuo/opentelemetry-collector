#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
#
# Shared helpers for the OTAP embedding spikes. Each run.sh sources this file.
# shellcheck shell=bash

SPIKES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_OUT="${SPIKE_OUT:-${TMPDIR:-/tmp}/otap-spikes}"

# workdir NAME prints a fresh copy of spike NAME under $SPIKE_OUT, so builds
# never write into the repository.
workdir() {
	local dst="$SPIKE_OUT/$1"
	rm -rf "$dst"
	mkdir -p "$dst"
	cp -R "$SPIKES_DIR/$1/." "$dst/"
	printf '%s\n' "$dst"
}

# find_zig prints the zig binary: $ZIG, then zig on PATH, then the ziglang wheel.
find_zig() {
	if [ -n "${ZIG:-}" ]; then
		printf '%s\n' "$ZIG"
	elif command -v zig >/dev/null 2>&1; then
		command -v zig
	else
		python3 -c 'import os, ziglang; print(os.path.join(os.path.dirname(ziglang.__file__), "zig"))'
	fi
}

# make_zig_wrappers DIR TARGET... writes zcc-TARGET, zcxx-TARGET and zar into DIR.
# Go's CC, Rust's cc crate and autoconf each accept a single executable path.
make_zig_wrappers() {
	local dir="$1" zig t mode name
	shift
	zig="$(find_zig)"
	mkdir -p "$dir"
	for t in "$@"; do
		for mode in cc c++; do
			name="zcc-$t"
			[ "$mode" = "c++" ] && name="zcxx-$t"
			cat >"$dir/$name" <<WRAPPER
#!/bin/sh
# zig $mode pinned to $t. Rust's cc crate appends --target=<rust triple>,
# which Zig cannot parse, so drop it and keep the pinned Zig target.
for a in "\$@"; do
	shift
	case "\$a" in
	--target=*) ;;
	*) set -- "\$@" "\$a" ;;
	esac
done
exec "$zig" $mode -target $t "\$@"
WRAPPER
			chmod +x "$dir/$name"
		done
	done
	# shellcheck disable=SC2016 # "$@" belongs to the generated script
	printf '#!/bin/sh\nexec "%s" ar "$@"\n' "$zig" >"$dir/zar"
	chmod +x "$dir/zar"
}

# run_native BINARY_PREFIX runs the build that matches this machine, if any.
run_native() {
	local bin
	case "$(uname -m)" in
	x86_64) bin="./$1amd64" ;;
	aarch64 | arm64) bin="./$1arm64" ;;
	*) bin="" ;;
	esac
	if [ -n "$bin" ] && [ -x "$bin" ]; then "$bin"; else echo "no native binary to run on $(uname -m)"; fi
}
