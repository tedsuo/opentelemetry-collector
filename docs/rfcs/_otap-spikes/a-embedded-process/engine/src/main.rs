// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

//! Stand-in for df_engine in "embedded process" mode. Speaks a line-based
//! control protocol on an inherited fd: READY -> (DRAIN -> DRAINED) -> SHUTDOWN -> EXITED.
use std::io::{BufRead, BufReader, Write};
use std::os::fd::FromRawFd;
use std::os::unix::net::UnixStream;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

fn main() {
    let fd: i32 = std::env::var("OTAP_CTL_FD").ok().and_then(|v| v.parse().ok()).unwrap_or(3);
    // SAFETY: the host passes us exactly one inherited socket at this fd.
    let ctl = unsafe { UnixStream::from_raw_fd(fd) };
    let mut out = ctl.try_clone().expect("clone ctl");
    let running = Arc::new(AtomicBool::new(true));
    let processed = Arc::new(AtomicU64::new(0));
    // Simulated thread-per-core pipeline workers.
    let workers: Vec<_> = (0..2).map(|_| {
        let (r, p) = (running.clone(), processed.clone());
        std::thread::spawn(move || while r.load(Ordering::Relaxed) {
            p.fetch_add(1, Ordering::Relaxed);
            std::thread::sleep(Duration::from_millis(5));
        })
    }).collect();
    writeln!(out, "READY pid={} arch={}", std::process::id(), std::env::consts::ARCH).unwrap();
    for line in BufReader::new(ctl).lines() {
        let line = match line { Ok(l) => l, Err(_) => break };
        match line.split_whitespace().next() {
            Some("DRAIN") => {
                running.store(false, Ordering::Relaxed);
                writeln!(out, "DRAINED processed={}", processed.load(Ordering::Relaxed)).unwrap();
            }
            Some("SHUTDOWN") => break,
            _ => writeln!(out, "ERR unknown command").unwrap(),
        }
    }
    // EOF on the control socket also lands here: the host is gone, so exit.
    running.store(false, Ordering::Relaxed);
    for w in workers { let _ = w.join(); }
    let _ = writeln!(out, "EXITED code=0");
}
