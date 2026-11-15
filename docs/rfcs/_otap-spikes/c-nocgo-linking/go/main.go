// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

// Spikes C1 and C2: call Rust code linked as a .syso, with CGO_ENABLED=0.
package main

import "fmt"

// rsAdd is implemented in trampoline_amd64.s and calls rs_add in the .syso.
func rsAdd(a, b uint64) uint64

func main() { fmt.Println("rs_add(40, 2) =", rsAdd(40, 2)) }
