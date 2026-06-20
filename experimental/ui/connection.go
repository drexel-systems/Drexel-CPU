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
	respCh   chan string // hex-address lines forwarded from the drain goroutine
}

// send writes a single command to the Renode monitor (fire-and-forget).
func (mc *monitorConn) send(cmd string) tea.Cmd {
	return func() tea.Msg {
		fmt.Fprintf(mc.w, "%s\n", cmd)
		mc.w.Flush()
		return nil
	}
}

// pollPC sends "cpu PC" to the monitor; the response arrives later on respCh.
func (mc *monitorConn) pollPC() tea.Cmd {
	return mc.send("cpu PC")
}

// sendSeq writes multiple monitor commands in a single goroutine so they are
// never interleaved with other concurrent sends. All lines are written before
// the single Flush call. Use this for any multi-command sequence (e.g. reset)
// where order and atomicity both matter.
func (mc *monitorConn) sendSeq(cmds ...string) tea.Cmd {
	return func() tea.Msg {
		for _, cmd := range cmds {
			fmt.Fprintf(mc.w, "%s\n", cmd)
		}
		mc.w.Flush()
		return nil
	}
}

// close shuts down both TCP connections. The UART goroutine and the drain
// goroutine detect the error, exit, and close their channels naturally.
func (mc *monitorConn) close() tea.Cmd {
	return func() tea.Msg {
		mc.uartConn.Close()
		mc.conn.Close()
		return nil
	}
}

// ── Messages ──────────────────────────────────────────────────────────────────

type connectedMsg struct {
	mon         *monitorConn
	uartCh      chan string
	initGPIOOut uint32 // GPIO_OUT at connect time — seeds LED state
}

type connectErrMsg struct{ err error }

// uartDataMsg carries raw bytes from the UART socket.
type uartDataMsg string

// uartErrMsg is sent when the UART connection drops.
type uartErrMsg struct{ err error }

// monRespMsg carries a hex-address line received from the monitor drain.
// Used by the CPU PC polling feature.
type monRespMsg string

// ── Connect command ───────────────────────────────────────────────────────────

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

		// Sync LED state before starting the drain goroutine.
		initGPIOOut := syncGPIOOut(monConn)

		// respCh receives hex-address lines (e.g. "cpu PC" responses) from
		// the drain goroutine so the model can do CPU state detection.
		respCh := make(chan string, 8)

		// Drain goroutine — reads the monitor line-by-line and forwards any
		// line that looks like a hex address (starts with "0x") to respCh.
		// Everything else (prompts, echo, help text) is silently discarded.
		go func() {
			defer close(respCh)
			scanner := bufio.NewScanner(monConn)
			for scanner.Scan() {
				line := strings.TrimSpace(scanner.Text())
				if strings.HasPrefix(strings.ToLower(line), "0x") {
					select {
					case respCh <- strings.ToLower(line):
					default: // channel full — drop; next poll will catch it
					}
				}
			}
		}()

		// Stream raw UART bytes so partial output (individual '.' dots)
		// appears immediately without waiting for a newline.
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

		return connectedMsg{
			mon: &monitorConn{
				conn:     monConn,
				uartConn: uartConn,
				w:        bufio.NewWriter(monConn),
				respCh:   respCh,
			},
			uartCh:      uartCh,
			initGPIOOut: initGPIOOut,
		}
	}
}

// ── Sync helpers ──────────────────────────────────────────────────────────────

// syncGPIOOut reads the LED output register from the Renode monitor so the UI
// can mirror actual hardware state on connect (important after power-cycle).
//
//  1. Drain banner/prompt lines (150 ms timeout).
//  2. Send "sysbus ReadDoubleWord 0xe0015000".
//  3. Read until a "0x…" line arrives (500 ms timeout).
//
// Returns 0 on any error — safe default for a fresh session.
func syncGPIOOut(conn net.Conn) uint32 {
	r := bufio.NewReader(conn)

	conn.SetReadDeadline(time.Now().Add(150 * time.Millisecond))
	for {
		if _, err := r.ReadString('\n'); err != nil {
			break
		}
	}
	conn.SetReadDeadline(time.Time{})

	fmt.Fprintf(conn, "sysbus ReadDoubleWord 0xe0015000\n")

	conn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	defer conn.SetReadDeadline(time.Time{})
	for {
		line, err := r.ReadString('\n')
		lower := strings.ToLower(strings.TrimSpace(line))
		if strings.HasPrefix(lower, "0x") {
			if val, e := strconv.ParseUint(lower[2:], 16, 32); e == nil {
				return uint32(val)
			}
		}
		if err != nil {
			return 0
		}
	}
}

// ── Wait helpers ──────────────────────────────────────────────────────────────

// waitUART blocks until the next raw UART chunk arrives.
func waitUART(ch chan string) tea.Cmd {
	return func() tea.Msg {
		chunk, ok := <-ch
		if !ok {
			return uartErrMsg{fmt.Errorf("connection closed")}
		}
		return uartDataMsg(chunk)
	}
}

// waitMonResp blocks until the drain goroutine forwards the next monitor
// response (a hex-address line). Returns nil if the channel is closed.
func waitMonResp(ch chan string) tea.Cmd {
	return func() tea.Msg {
		resp, ok := <-ch
		if !ok {
			return nil // connection gone; stop waiting
		}
		return monRespMsg(resp)
	}
}
