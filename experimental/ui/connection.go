package main

import (
	"bufio"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// ── Monitor connection ────────────────────────────────────────────────────────

type monitorConn struct {
	conn     net.Conn
	uartConn net.Conn
	w        *bufio.Writer
}

// send writes a command to the Renode monitor.
func (mc *monitorConn) send(cmd string) tea.Cmd {
	return func() tea.Msg {
		fmt.Fprintf(mc.w, "%s\n", cmd)
		mc.w.Flush()
		return nil
	}
}

// close shuts down both TCP connections; the UART goroutine will detect the
// error and close the channel naturally.
func (mc *monitorConn) close() tea.Cmd {
	return func() tea.Msg {
		mc.uartConn.Close()
		mc.conn.Close()
		return nil
	}
}

// ── Messages ──────────────────────────────────────────────────────────────────

type connectedMsg struct {
	mon        *monitorConn
	uartCh     chan string
	initGPIOOut uint32 // value of GPIO_OUT at connect time — used to sync LED state
}

type connectErrMsg struct{ err error }

// uartDataMsg carries raw bytes from the UART socket — may be a partial line,
// a full line, or multiple lines. The model splits on newlines.
type uartDataMsg string
type uartErrMsg struct{ err error }

// ── Connect command ───────────────────────────────────────────────────────────

// connectCmd tries to open both sockets. Runs in a goroutine via bubbletea.
func connectCmd(monPort, uartPort int) tea.Cmd {
	return func() tea.Msg {
		monConn, err := net.DialTimeout("tcp",
			fmt.Sprintf("localhost:%d", monPort), 3*time.Second)
		if err != nil {
			return connectErrMsg{fmt.Errorf(
				"can't reach Renode monitor on port %d\nIs Renode running? (make run)", monPort)}
		}

		uartConn, err := net.DialTimeout("tcp",
			fmt.Sprintf("localhost:%d", uartPort), 3*time.Second)
		if err != nil {
			monConn.Close()
			return connectErrMsg{fmt.Errorf(
				"can't reach UART on port %d\nIs Renode running? (make run)", uartPort)}
		}

		// Sync LED state from GPIO_OUT before handing the connection to the
		// drain goroutine.  Renode keeps running across UI power-cycles, so
		// the hardware LED state may differ from the UI's assumed all-off.
		initGPIOOut := syncGPIOOut(monConn)

		// Stream raw UART bytes into a channel — don't buffer by line so that
		// partial output (e.g. individual '.' dots) appears immediately.
		uartCh := make(chan string, 256)
		go func() {
			defer close(uartCh)
			buf := make([]byte, 256)
			for {
				n, err := uartConn.Read(buf)
				if n > 0 {
					uartCh <- string(buf[:n])
				}
				if err != nil {
					return
				}
			}
		}()

		// Start drain goroutine now that the sync read is done.
		go func() {
			buf := make([]byte, 4096)
			for {
				if _, err := monConn.Read(buf); err != nil {
					return
				}
			}
		}()

		return connectedMsg{
			mon: &monitorConn{
				conn:     monConn,
				uartConn: uartConn,
				w:        bufio.NewWriter(monConn),
			},
			uartCh:      uartCh,
			initGPIOOut: initGPIOOut,
		}
	}
}

// syncGPIOOut reads the GPIO output register from the Renode monitor so the
// UI can mirror the actual hardware LED state on connect.
//
// Protocol:
//   1. Drain any banner/prompt lines (100 ms timeout).
//   2. Send "sysbus ReadDoubleWord 0xe0015000".
//   3. Read until we get a line starting with "0x" (500 ms timeout).
//
// Returns 0 on any error — LEDs will default to off, which is correct for a
// fresh Renode session and merely cosmetically wrong if reconnecting mid-run.
func syncGPIOOut(conn net.Conn) uint32 {
	r := bufio.NewReader(conn)

	// Step 1: drain banner / prompt with a short timeout.
	conn.SetReadDeadline(time.Now().Add(150 * time.Millisecond))
	for {
		_, err := r.ReadString('\n')
		if err != nil {
			break
		}
	}
	conn.SetReadDeadline(time.Time{})

	// Step 2: request GPIO_OUT value.
	fmt.Fprintf(conn, "sysbus ReadDoubleWord 0xe0015000\n")

	// Step 3: read response lines until we find the hex value.
	conn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	defer conn.SetReadDeadline(time.Time{})
	for {
		line, err := r.ReadString('\n')
		line = strings.TrimSpace(line)
		lower := strings.ToLower(line)
		if strings.HasPrefix(lower, "0x") {
			val, parseErr := strconv.ParseUint(lower[2:], 16, 32)
			if parseErr == nil {
				return uint32(val)
			}
		}
		if err != nil {
			return 0
		}
	}
}

// waitUART blocks until the next chunk of UART data arrives.
func waitUART(ch chan string) tea.Cmd {
	return func() tea.Msg {
		chunk, ok := <-ch
		if !ok {
			return uartErrMsg{fmt.Errorf("connection closed")}
		}
		return uartDataMsg(chunk)
	}
}
