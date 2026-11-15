// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

//! Spikes C1 and C2: Rust code for Go's internal linker to link as a `.syso`.

/// Pure arithmetic: no libc, no TLS.
#[unsafe(no_mangle)]
pub extern "C" fn rs_add(a: u64, b: u64) -> u64 {
    a.wrapping_add(b)
}

#[cfg(feature = "tls")]
mod tls {
    use std::cell::Cell;

    thread_local! { static COUNTER: Cell<u64> = const { Cell::new(0) }; }

    /// Touches a Rust thread-local.
    #[unsafe(no_mangle)]
    pub extern "C" fn rs_tls_bump() -> u64 {
        COUNTER.with(|c| {
            c.set(c.get() + 1);
            c.get()
        })
    }
}
