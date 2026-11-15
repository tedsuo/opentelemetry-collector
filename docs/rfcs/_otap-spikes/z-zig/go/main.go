// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

package main

/*
#cgo linux,amd64 LDFLAGS: ${SRCDIR}/lib/linux_amd64/librsengine.a -lunwind
#cgo linux,arm64 LDFLAGS: ${SRCDIR}/lib/linux_arm64/librsengine.a -lunwind
#cgo windows,amd64 LDFLAGS: ${SRCDIR}/lib/windows_amd64/librsengine.a -lkernel32 -lntdll -luserenv -lws2_32 -ldbghelp -lunwind
#cgo darwin,arm64 LDFLAGS: ${SRCDIR}/lib/darwin_arm64/librsengine.a -lSystem -lm
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
	"runtime"
	"sync"
	"syscall"
	"time"
)

func main() {
	C.engine_start(2)
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ { // Rust TLS used from many Go threads
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 1000; j++ {
				C.engine_tls_bump()
			}
		}()
	}
	wg.Wait()
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	selfTerminate()
	select {
	case s := <-sig:
		fmt.Printf("go %s/%s: got %v while Rust threads run; shutting the engine down\n", runtime.GOOS, runtime.GOARCH, s)
	case <-time.After(2 * time.Second):
		fmt.Println("go: no signal; shutting the engine down")
	}
	fmt.Println("go: engine drained, did work:", uint64(C.engine_shutdown()) > 0)
}
