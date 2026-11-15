// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

//go:build unix

package main

import (
	"os"
	"syscall"
	"time"
)

func selfTerminate() {
	go func() { time.Sleep(50 * time.Millisecond); _ = syscall.Kill(os.Getpid(), syscall.SIGTERM) }()
}
