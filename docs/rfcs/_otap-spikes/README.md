# OTAP engine embedding spikes

Small experiments behind the project plan for compiling the OTAP Dataflow Engine
from [otel-arrow](https://github.com/open-telemetry/otel-arrow) into Collector
binaries built by OCB. Each directory reproduces spikes from the plan's evidence
table. Nothing here is production code.

The directory name starts with `_` so Go patterns such as `./...` skip it, and it
holds no `go.mod` files, so the repository's module tooling ignores it. Each
`run.sh` copies its sources to `$SPIKE_OUT` (default `$TMPDIR/otap-spikes`) and
builds there, so runs leave this tree untouched.

## Results

Observed on 2026-11-15 on Linux x86-64 (4 cores) with Go 1.26.0, Rust 1.97.0 and
Zig 0.17.1. The arm64, Windows and macOS binaries were built but not run.

| Spike | Directory | Experiment | Result |
| --- | --- | --- | --- |
| A | `a-embedded-process` | Plan A: a static musl engine stub, built with Rust's `rust-lld` and no C toolchain, embedded in a `CGO_ENABLED=0` Go host, launched from `memfd`, driven over a socketpair | Works on amd64 and arm64; ready in about 1 ms; SIGTERM drains and stops the engine |
| C1 | `c-nocgo-linking` | A Rust static library with a thread-local, linked as a `.syso` by Go's internal linker | Fails: `reloc of invalid sym ... type=6` (`STT_TLS`) |
| C2 | `c-nocgo-linking` | The same with a TLS-free function | Works |
| C3 | `c-nocgo-linking` | `-linkmode=external` with `CGO_ENABLED=0` | Refused |
| B1 | `b-cgo` | Plan B: cgo with a Rust static library and the host toolchain | Works; Go keeps SIGTERM while Rust threads run |
| B2 | `b-cgo` | cgo cross-build to linux/arm64 without a target sysroot | Fails on missing libc headers |
| Z1 to Z4 | `z-zig` | Plan Z: the B1 program cross-built with Zig for linux/amd64, linux/arm64, windows/amd64 and darwin/arm64 | All four link and amd64 runs. Windows needs `-lunwind`; macOS needs the stubs in `macos-stubs` |
| Z5, Z6 | `z-zig-engine` | Plan Z: the real engine as a static library inside a Go process, with ring, jemalloc and zstd compiled by Zig | amd64: ready in 11 ms, and Go drains it on SIGTERM in 4 ms. arm64 cross-builds in about 12 minutes |

## Prerequisites

- Go 1.26 and Rust 1.97, with the targets these spikes use:
  `rustup target add x86_64-unknown-linux-musl aarch64-unknown-linux-musl x86_64-pc-windows-gnu aarch64-apple-darwin`
- `ld` from binutils, `file`, and for `b-cgo`, gcc and clang.
- Zig 0.17.1 for the `z-*` spikes: set `$ZIG`, put `zig` on `PATH`, or `pip install ziglang`.
- For `z-zig-engine`: an otel-arrow checkout at `8312b7a` in `$OTEL_ARROW_DIR`, with
  `z-zig-engine/otel-arrow-musl.patch` applied. Without it the engine doesn't build
  for musl targets, because nix omits `XFS_SUPER_MAGIC` on musl.

## Running

```bash
docs/rfcs/_otap-spikes/a-embedded-process/run.sh
docs/rfcs/_otap-spikes/c-nocgo-linking/run.sh
docs/rfcs/_otap-spikes/b-cgo/run.sh
docs/rfcs/_otap-spikes/z-zig/run.sh
OTEL_ARROW_DIR=../otel-arrow docs/rfcs/_otap-spikes/z-zig-engine/run.sh
```

`z-zig-engine` builds amd64 and arm64 by default, about 10 minutes each on 4 cores.
Set `ARCHES=amd64` to build one target, and `CARGO_TARGET_DIR` to reuse a build cache.

## Notes

- Rust's `cc` crate passes `--target=<rust triple>`, which Zig rejects. The wrappers
  that `common.sh` generates drop that flag and keep their pinned Zig target.
- The macOS stubs list only symbol names and install names, the way Zig ships its
  own libSystem stub. Shipping stubs like these needs legal review.
- Go's `runtime/cgo` always links CoreFoundation on darwin/arm64, and `os` pulls in
  libresolv, so even a minimal cgo build for macOS needs both.
