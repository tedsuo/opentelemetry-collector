// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

//go:build linux && amd64

package main

import _ "embed"

//go:embed bin/engine_linux_amd64
var engineImage []byte
