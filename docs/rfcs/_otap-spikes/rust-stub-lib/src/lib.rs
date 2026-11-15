// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

use std::cell::Cell;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::OnceLock;
use std::thread::JoinHandle;
use std::sync::Mutex;

thread_local! { static CALLS: Cell<u64> = const { Cell::new(0) }; }
static RUNNING: AtomicBool = AtomicBool::new(false);
static WORK: AtomicU64 = AtomicU64::new(0);
static WORKERS: OnceLock<Mutex<Vec<JoinHandle<()>>>> = OnceLock::new();

/// Start N engine-owned worker threads (stand-in for the thread-per-core runtime).
#[unsafe(no_mangle)]
pub extern "C" fn engine_start(n: u32) -> i32 {
    RUNNING.store(true, Ordering::SeqCst);
    let ws = WORKERS.get_or_init(|| Mutex::new(Vec::new()));
    for _ in 0..n {
        ws.lock().unwrap().push(std::thread::spawn(|| while RUNNING.load(Ordering::Relaxed) {
            CALLS.with(|c| c.set(c.get() + 1));
            WORK.fetch_add(1, Ordering::Relaxed);
            std::thread::sleep(std::time::Duration::from_millis(2));
        }));
    }
    0
}

/// Called from Go goroutines: exercises Rust TLS on Go-created threads.
#[unsafe(no_mangle)]
pub extern "C" fn engine_tls_bump() -> u64 { CALLS.with(|c| { c.set(c.get() + 1); c.get() }) }

/// Coordinated shutdown: stop and join workers, report work done.
#[unsafe(no_mangle)]
pub extern "C" fn engine_shutdown() -> u64 {
    RUNNING.store(false, Ordering::SeqCst);
    if let Some(ws) = WORKERS.get() { for w in ws.lock().unwrap().drain(..) { let _ = w.join(); } }
    WORK.load(Ordering::Relaxed)
}
