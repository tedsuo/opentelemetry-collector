// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

// Spike B1: a Rust static library whose threads and thread-locals are used from
// many goroutines, linked with cgo; Go keeps ownership of SIGTERM.
package main

/*
#cgo linux,amd64 LDFLAGS: ${SRCDIR}/lib/librsengine.a -lpthread -ldl -lm
#include <stdint.h>
int32_t engine_start(uint32_t n);
uint64_t engine_tls_bump(void);
uint64_t engine_shutdown(void);
*/
import "C"

import (
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

func main() {
	C.engine_start(2)
	var wg sync.WaitGroup
	for range 8 { // Rust TLS used from many Go threads
		wg.Add(1)
		go func() {
			defer wg.Done()
			for range 1000 {
				C.engine_tls_bump()
			}
		}()
	}
	wg.Wait()
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM)
	go func() { time.Sleep(50 * time.Millisecond); _ = syscall.Kill(os.Getpid(), syscall.SIGTERM) }()
	fmt.Println("go: received", <-sig, "while Rust threads run; shutting the engine down")
	fmt.Println("go: engine drained, did work:", uint64(C.engine_shutdown()) > 0)
}
