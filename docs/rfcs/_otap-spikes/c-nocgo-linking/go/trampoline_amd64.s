// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

#include "textflag.h"

// func rsAdd(a, b uint64) uint64 (ABI0 to System V; leaf call, no stack switch)
TEXT ·rsAdd(SB), NOSPLIT, $0-24
	MOVQ a+0(FP), DI
	MOVQ b+8(FP), SI
	CALL rs_add(SB)
	MOVQ AX, ret+16(FP)
	RET
