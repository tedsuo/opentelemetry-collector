// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

//! Plan Z spike: the real OTAP Dataflow Engine controller behind a minimal C ABI,
//! linked into a Go process with cgo and built with Zig.

use otel_arrow_dfe_admin::ControlPlane;
use otel_arrow_dfe_config::engine::OtelDataflowSpec;
use otel_arrow_dfe_controller::{
    BuildInfo, Controller, ControllerExtensionContext, ControllerExtensionError,
    ControllerExtensionRegistry, ControllerExtensionTask, ControllerExtensionTaskFactory,
    ControllerRunOptions,
};
// Linked for its `linkme` registrations: receiver:otlp and exporter:noop.
use otel_arrow_dfe_core_nodes as _;
use otel_arrow_dfe_otap::OTAP_PIPELINE_FACTORY;
use std::ffi::{CStr, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::JoinHandle;
use tokio_util::sync::CancellationToken;

#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;

const HOST_EXTENSION_URN: &str = "urn:otel:extension:spike_host";
const STARTING: i32 = 1;
const READY: i32 = 2;
const STOPPED: i32 = 3;
const FAILED: i32 = -1;

static STATE: AtomicI32 = AtomicI32::new(0);
static CONTROL: OnceLock<Arc<dyn ControlPlane>> = OnceLock::new();
static RUNNER: Mutex<Option<JoinHandle<i32>>> = Mutex::new(None);

/// Host controller extension: hands the control plane to the host, then idles until cancelled.
fn host_extension(
    ctx: ControllerExtensionContext,
) -> Result<ControllerExtensionTaskFactory, ControllerExtensionError> {
    let _ = CONTROL.set(Arc::clone(&ctx.control_plane));
    STATE.store(READY, Ordering::SeqCst);
    Ok(Box::new(|token: CancellationToken| -> ControllerExtensionTask {
        Box::pin(async move {
            token.cancelled().await;
            Ok(())
        })
    }))
}

fn run(yaml: String) -> i32 {
    if let Err(e) = otel_arrow_dfe_otap::crypto::install_crypto_provider() {
        eprintln!("spike: crypto provider: {e}");
        return 2;
    }
    let spec = match OtelDataflowSpec::from_yaml(&yaml) {
        Ok(spec) => spec,
        Err(e) => {
            eprintln!("spike: config: {e}");
            return 3;
        }
    };
    let mut extensions = ControllerExtensionRegistry::default();
    extensions.register(HOST_EXTENSION_URN.into(), host_extension, |_| Ok(()));
    let options = ControllerRunOptions {
        extensions,
        build_info: BuildInfo {
            service_name: Some("otelcol-otap-spike".into()),
            service_version: None,
        },
        handle_os_signals: false, // the Go host owns signals
        ..Default::default()
    };
    match Controller::new(&OTAP_PIPELINE_FACTORY).run_forever_with_options(spec, options) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("spike: controller: {e}");
            4
        }
    }
}

/// Starts the engine on an engine-owned thread. Returns 0 when the thread is running.
#[unsafe(no_mangle)]
pub extern "C" fn otap_engine_start(config_yaml: *const c_char) -> i32 {
    if config_yaml.is_null() {
        return -1;
    }
    // SAFETY: the host passes a NUL-terminated string that outlives this call.
    let yaml = unsafe { CStr::from_ptr(config_yaml) }.to_string_lossy().into_owned();
    STATE.store(STARTING, Ordering::SeqCst);
    let spawned = std::thread::Builder::new()
        .name("otap-controller".into())
        .spawn(move || {
            let code = catch_unwind(AssertUnwindSafe(|| run(yaml))).unwrap_or(5);
            STATE.store(if code == 0 { STOPPED } else { FAILED }, Ordering::SeqCst);
            code
        });
    match spawned {
        Ok(handle) => {
            *RUNNER.lock().unwrap_or_else(|p| p.into_inner()) = Some(handle);
            0
        }
        Err(_) => -2,
    }
}

/// 0 idle, 1 starting, 2 ready, 3 stopped, -1 failed.
#[unsafe(no_mangle)]
pub extern "C" fn otap_engine_state() -> i32 {
    STATE.load(Ordering::SeqCst)
}

/// Graceful shutdown: drain every pipeline, then join the controller thread.
/// Returns the controller's exit code, or a negative value if the request failed.
#[unsafe(no_mangle)]
pub extern "C" fn otap_engine_shutdown(timeout_secs: u64) -> i32 {
    let requested = catch_unwind(AssertUnwindSafe(|| match CONTROL.get() {
        Some(control) => control.shutdown_all(timeout_secs).is_ok(),
        None => false,
    }))
    .unwrap_or(false);
    if !requested {
        return -3;
    }
    let handle = RUNNER.lock().unwrap_or_else(|p| p.into_inner()).take();
    match handle.map(JoinHandle::join) {
        Some(Ok(code)) => code,
        Some(Err(_)) => 6,
        None => -1,
    }
}
