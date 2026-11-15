// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

// Plan Z spike: the real OTAP Dataflow Engine running inside a Go process via cgo,
// with Go owning signals and driving coordinated startup and shutdown.
package main

/*
#cgo linux,amd64 LDFLAGS: ${SRCDIR}/lib/linux_amd64/libotap_host_ffi.a -lunwind
#cgo linux,arm64 LDFLAGS: ${SRCDIR}/lib/linux_arm64/libotap_host_ffi.a -lunwind
#include <stdint.h>
#include <stdlib.h>
int32_t otap_engine_start(const char* config_yaml);
int32_t otap_engine_state(void);
int32_t otap_engine_shutdown(uint64_t timeout_secs);
*/
import "C"

import (
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"
	"unsafe"
)

const engineConfig = `
version: otel_dataflow/v1
engine:
  http_admin:
    bind_address: "127.0.0.1:18080"
  controller:
    extensions:
      host:
        type: "urn:otel:extension:spike_host"
        config: {}
policies:
  resources:
    core_allocation:
      type: core_count
      count: 1
groups:
  default:
    pipelines:
      main:
        nodes:
          receiver:
            type: receiver:otlp
            config:
              protocols:
                grpc:
                  listening_addr: "127.0.0.1:44317"
          exporter:
            type: exporter:noop
            config: {}
        connections:
          - from: receiver
            to: exporter
`

func dialOK(addr string, within time.Duration) bool {
	deadline := time.Now().Add(within)
	for time.Now().Before(deadline) {
		if c, err := net.DialTimeout("tcp", addr, 200*time.Millisecond); err == nil {
			c.Close()
			return true
		}
		time.Sleep(20 * time.Millisecond)
	}
	return false
}

func main() {
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM, os.Interrupt) // Go owns process signals

	t0 := time.Now()
	cfg := C.CString(engineConfig)
	defer C.free(unsafe.Pointer(cfg))
	if rc := C.otap_engine_start(cfg); rc != 0 {
		fmt.Println("go: engine start failed:", rc)
		os.Exit(1)
	}
	for C.otap_engine_state() == 1 && time.Since(t0) < 30*time.Second {
		time.Sleep(10 * time.Millisecond)
	}
	if st := C.otap_engine_state(); st != 2 {
		fmt.Println("go: engine did not become ready, state", st)
		os.Exit(1)
	}
	fmt.Printf("go: engine ready in-process after %v (pid %d)\n", time.Since(t0).Round(time.Millisecond), os.Getpid())
	fmt.Println("go: engine OTLP receiver listening on 127.0.0.1:44317:", dialOK("127.0.0.1:44317", 3*time.Second))

	go func() { time.Sleep(300 * time.Millisecond); _ = syscall.Kill(os.Getpid(), syscall.SIGTERM) }()
	fmt.Println("go: received", <-sig, "- asking the engine to drain and stop")
	t1 := time.Now()
	rc := C.otap_engine_shutdown(10)
	fmt.Printf("go: engine controller returned %d after %v, state %d\n", rc, time.Since(t1).Round(time.Millisecond), C.otap_engine_state())
	fmt.Println("go: OTLP port still open after shutdown:", dialOK("127.0.0.1:44317", 300*time.Millisecond))
}
