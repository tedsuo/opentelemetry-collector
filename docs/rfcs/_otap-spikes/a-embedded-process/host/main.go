// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

//go:build linux

// Stand-in for the Collector-side engine host: materializes the embedded
// engine without touching disk (memfd), supervises it, and coordinates
// startup/shutdown over an inherited socketpair. Built with CGO_ENABLED=0.
package main

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

func main() {
	// 1. Materialize the embedded engine as an anonymous in-memory file.
	mfd, err := unix.MemfdCreate("otap-engine", unix.MFD_CLOEXEC)
	must(err)
	_, err = unix.Write(mfd, engineImage)
	must(err)

	// 2. Control channel: one end stays here, the other becomes fd 3 in the child.
	fds, err := unix.Socketpair(unix.AF_UNIX, unix.SOCK_STREAM|unix.SOCK_CLOEXEC, 0)
	must(err)
	parentEnd, childEnd := os.NewFile(uintptr(fds[0]), "ctl"), os.NewFile(uintptr(fds[1]), "ctl-child")
	conn, err := net.FileConn(parentEnd)
	must(err)

	cmd := exec.Command(fmt.Sprintf("/proc/self/fd/%d", mfd))
	cmd.Args = []string{"otap-engine"}
	cmd.Env = []string{"OTAP_CTL_FD=3"}
	cmd.ExtraFiles = []*os.File{childEnd}
	cmd.Stderr = os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid:   true,            // terminal Ctrl-C goes to the host only; the host coordinates
		Pdeathsig: syscall.SIGKILL, // engine never outlives the host
	}
	start := time.Now()
	must(cmd.Start())
	childEnd.Close()

	lines := bufio.NewScanner(conn)
	expect := func(prefix string, timeout time.Duration) string {
		_ = conn.SetReadDeadline(time.Now().Add(timeout))
		if !lines.Scan() || !strings.HasPrefix(lines.Text(), prefix) {
			fmt.Fprintf(os.Stderr, "host: expected %s, got %q (%v)\n", prefix, lines.Text(), lines.Err())
			_ = cmd.Process.Kill()
			os.Exit(1)
		}
		return lines.Text()
	}

	// 3. Coordinated startup: Collector pipelines would start only after READY.
	fmt.Printf("host: engine says %q after %v\n", expect("READY", 5*time.Second), time.Since(start).Round(time.Millisecond))

	// 4. Run until SIGTERM/SIGINT (or a demo timeout), as the Collector does.
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM, os.Interrupt)
	select {
	case s := <-sig:
		fmt.Printf("host: got %v, starting coordinated shutdown\n", s)
	case <-time.After(300 * time.Millisecond):
		fmt.Println("host: demo timeout, starting coordinated shutdown")
	}

	// 5. Coordinated shutdown: drain, then stop, with a hard deadline.
	fmt.Fprintln(conn, "DRAIN deadline_ms=5000")
	fmt.Printf("host: engine says %q\n", expect("DRAINED", 5*time.Second))
	fmt.Fprintln(conn, "SHUTDOWN")
	fmt.Printf("host: engine says %q\n", expect("EXITED", 5*time.Second))
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		fmt.Printf("host: engine process exited, err=%v\n", err)
	case <-time.After(5 * time.Second):
		_ = cmd.Process.Kill()
		fmt.Println("host: engine missed deadline, killed")
	}
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
