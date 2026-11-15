// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

//go:build linux && arm64

package main

import _ "embed"

//go:embed bin/engine_linux_arm64
var engineImage []byte
