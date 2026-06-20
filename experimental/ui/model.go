package main

import (
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── Board state machine ───────────────────────────────────────────────────────

type boardState int

const (
	stPoweredDown boardState = iota
	stConnecting
	stStartup   // running the self-test animation
	stPostTest  // showing "POST OK" for 2 seconds before going live
	stRunning
	stError
)

// ── Startup sequence ──────────────────────────────────────────────────────────

// startupTickMsg carries the index of the next step to execute.
type startupTickMsg int

type startupAction struct {
	delay  time.Duration
	action func(m *model)
}

// startupSeq defines the self-test animation played on every power-up.
// Each entry: apply action immediately, then wait delay before the next entry.
var startupSeq = []startupAction{
	// LED test: cycle each LED on then off (300 ms per state)
	{300 * time.Millisecond, func(m *model) { m.leds[0] = true }},
	{300 * time.Millisecond, func(m *model) { m.leds[0] = false }},
	{300 * time.Millisecond, func(m *model) { m.leds[1] = true }},
	{300 * time.Millisecond, func(m *model) { m.leds[1] = false }},
	{300 * time.Millisecond, func(m *model) { m.leds[2] = true }},
	{300 * time.Millisecond, func(m *model) { m.leds[2] = false }},
	{300 * time.Millisecond, func(m *model) { m.leds[3] = true }},
	{300 * time.Millisecond, func(m *model) { m.leds[3] = false }},
	// Pause 1 second before DIP test
	{1 * time.Second, func(m *model) {}},
	// DIP test: toggle each switch on then off (1 s each)
	{1 * time.Second, func(m *model) { m.dips[0] = true }},
	{1 * time.Second, func(m *model) { m.dips[0] = false }},
	{1 * time.Second, func(m *model) { m.dips[1] = true }},
	{1 * time.Second, func(m *model) { m.dips[1] = false }},
	// 7-seg test: cycle digits 0–9 (500 ms each)
	{500 * time.Millisecond, func(m *model) { m.seg7 = 0x3F }}, // 0
	{500 * time.Millisecond, func(m *model) { m.seg7 = 0x06 }}, // 1
	{500 * time.Millisecond, func(m *model) { m.seg7 = 0x5B }}, // 2
	{500 * time.Millisecond, func(m *model) { m.seg7 = 0x4F }}, // 3
	{500 * time.Millisecond, func(m *model) { m.seg7 = 0x66 }}, // 4
	{500 * time.Millisecond, func(m *model) { m.seg7 = 0x6D }}, // 5
	{500 * time.Millisecond, func(m *model) { m.seg7 = 0x7D }}, // 6
	{500 * time.Millisecond, func(m *model) { m.seg7 = 0x07 }}, // 7
	{500 * time.Millisecond, func(m *model) { m.seg7 = 0x7F }}, // 8
	{500 * time.Millisecond, func(m *model) { m.seg7 = 0x6F }}, // 9
}

// postTestDoneMsg fires after the 2-second POST OK display.
type postTestDoneMsg struct{}

// startupTick schedules a delayed fire of startupTickMsg(step).
func startupTick(step int, delay time.Duration) tea.Cmd {
	return tea.Tick(delay, func(_ time.Time) tea.Msg {
		return startupTickMsg(step)
	})
}

// ── PC polling messages ───────────────────────────────────────────────────────

// pcPollTickMsg fires every second to trigger a "cpu PC" monitor query.
type pcPollTickMsg struct{}

// ── Model ─────────────────────────────────────────────────────────────────────

type model struct {
	// State machine
	state  boardState
	errMsg string

	// Self-test
	startupStep int

	// Hardware state (driven by startup sequence and UART parsing)
	leds [4]bool
	seg7 byte
	dips [4]bool

	// Connections
	mon    *monitorConn
	uartCh chan string

	// UART output
	uartLines   []string
	uartPartial string // bytes received that haven't yet ended with '\n'
	viewport    viewport.Model
	vpReady     bool

	// CPU state detection (PC polling)
	cpuHalted   bool
	lastPC      string
	pcSameCount int

	// Config
	monPort  int
	uartPort int

	// Terminal dimensions
	width  int
	height int
}

func newModel(monPort, uartPort int) model {
	return model{
		state:    stPoweredDown,
		seg7:     0x00, // blank when powered down
		monPort:  monPort,
		uartPort: uartPort,
	}
}

func (m model) Init() tea.Cmd { return nil }

// ── Update ────────────────────────────────────────────────────────────────────

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {

	// ── Window resize ─────────────────────────────────────────────────────────
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		vpW := msg.Width - 4
		vpH := vpHeight(msg.Height)
		if vpW < 10 {
			vpW = 10
		}
		if !m.vpReady {
			m.viewport = viewport.New(vpW, vpH)
			m.viewport.Style = lipgloss.NewStyle().Foreground(clrUART)
			m.vpReady = true
		} else {
			m.viewport.Width = vpW
			m.viewport.Height = vpH
		}
		if len(m.uartLines) > 0 || m.uartPartial != "" {
			m.viewport.SetContent(vpContent(&m))
			m.viewport.GotoBottom()
		}

	// ── Mouse (scroll) ────────────────────────────────────────────────────────
	case tea.MouseMsg:
		if m.vpReady {
			var cmd tea.Cmd
			m.viewport, cmd = m.viewport.Update(msg)
			cmds = append(cmds, cmd)
		}

	// ── Keyboard ──────────────────────────────────────────────────────────────
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "Q", "ctrl+c":
			return m, tea.Quit

		case "p", "P":
			switch m.state {
			case stPoweredDown, stError:
				m.state = stConnecting
				m.errMsg = ""
				cmds = append(cmds, connectCmd(m.monPort, m.uartPort))
			case stRunning, stStartup, stPostTest:
				old := m.mon
				m.mon = nil
				m.uartCh = nil
				m.state = stPoweredDown
				m.leds = [4]bool{}
				m.seg7 = 0x00
				m.dips = [4]bool{}
				m.uartPartial = ""
				m.cpuHalted = false
				m.lastPC = ""
				m.pcSameCount = 0
				cmds = append(cmds, old.close())
			}

		case "r", "R":
			if m.state == stRunning && m.mon != nil {
				// Soft-reset: pause → rewind PC to _start → resume.
				// We avoid "machine Reset" because that sends the CPU to the
				// RISC-V default reset vector (0x1000) which is outside our
				// ROM, causing an immediate abort. Instead we just rewind PC
				// to 0x20000000 (_start) so startup.S re-runs and re-inits
				// .data/.bss and peripherals without touching Renode state.
				m.leds = [4]bool{}
				m.seg7 = 0x3F // show "0" after reset
				m.dips = [4]bool{}
				m.cpuHalted = false
				m.lastPC = ""
				m.pcSameCount = 0
				m.uartLines = append(m.uartLines, "", "╌╌╌  Board Reset  ╌╌╌", "")
				m.uartPartial = ""
				if m.vpReady {
					m.viewport.SetContent(vpContent(&m))
					m.viewport.GotoBottom()
				}
				// Use sendSeq so all commands go to the monitor in one
				// goroutine — concurrent sends race on the shared Writer.
				// Clear GPIO_IN lines explicitly: the PC-rewind doesn't touch
				// peripheral registers, so Renode's GPIO state would otherwise
				// be out of sync with the UI's freshly-zeroed dips[].
				cmds = append(cmds,
					m.mon.sendSeq(
						"pause",
						"sysbus.gpio_in OnGPIO 0 False",
						"sysbus.gpio_in OnGPIO 1 False",
						"sysbus.gpio_in OnGPIO 2 False",
						"sysbus.gpio_in OnGPIO 3 False",
						"cpu PC 0x20000000",
						"start",
					),
				)
			}

		case "esc":
			// Skip the self-test / POST-OK banner and go straight to live mode.
			if (m.state == stStartup || m.state == stPostTest) && m.mon != nil {
				m.seg7 = 0x3F // show "0"
				m.leds = [4]bool{}
				m.dips = [4]bool{}
				m.state = stRunning
				if m.vpReady {
					m.viewport.SetContent(vpContent(&m))
					m.viewport.GotoBottom()
				}
				// Pending startupTickMsg / postTestDoneMsg will be dropped
				// because their handlers guard on m.state.
				// Kick off PC polling, which postTestDoneMsg would normally start.
				cmds = append(cmds,
					tea.Tick(1*time.Second, func(_ time.Time) tea.Msg { return pcPollTickMsg{} }),
					waitMonResp(m.mon.respCh),
				)
			}

		// Button presses — only active when fully running
		case "0":
			if m.state == stRunning && m.mon != nil {
				cmds = append(cmds, m.mon.send("runMacro $btn0Press"))
			}
		case "1":
			if m.state == stRunning && m.mon != nil {
				cmds = append(cmds, m.mon.send("runMacro $btn1Press"))
			}

		// DIP switches
		case "2":
			if m.state == stRunning && m.mon != nil {
				m.dips[0] = !m.dips[0]
				if m.dips[0] {
					cmds = append(cmds, m.mon.send("sysbus.gpio_in OnGPIO 2 True"))
				} else {
					cmds = append(cmds, m.mon.send("sysbus.gpio_in OnGPIO 2 False"))
				}
			}
		case "3":
			if m.state == stRunning && m.mon != nil {
				m.dips[1] = !m.dips[1]
				if m.dips[1] {
					cmds = append(cmds, m.mon.send("sysbus.gpio_in OnGPIO 3 True"))
				} else {
					cmds = append(cmds, m.mon.send("sysbus.gpio_in OnGPIO 3 False"))
				}
			}

		// UART scroll
		case "up", "k":
			if m.vpReady {
				m.viewport.LineUp(1)
			}
		case "down", "j":
			if m.vpReady {
				m.viewport.LineDown(1)
			}
		case "pgup":
			if m.vpReady {
				m.viewport.HalfViewUp()
			}
		case "pgdown":
			if m.vpReady {
				m.viewport.HalfViewDown()
			}
		}

	// ── Connection results ────────────────────────────────────────────────────
	case connectedMsg:
		m.mon = msg.mon
		m.uartCh = msg.uartCh
		// Blank everything and start the self-test animation.
		m.state = stStartup
		m.startupStep = 0
		m.leds = [4]bool{}
		m.seg7 = 0x00
		m.dips = [4]bool{}
		if m.vpReady {
			// Show the self-test banner immediately; UART content streams behind it.
			m.viewport.SetContent(vpContent(&m))
		}
		cmds = append(cmds,
			func() tea.Msg { return startupTickMsg(0) }, // fire first step immediately
			waitUART(m.uartCh),
		)

	case connectErrMsg:
		m.state = stError
		m.errMsg = msg.err.Error()

	// ── Startup self-test tick ────────────────────────────────────────────────
	case startupTickMsg:
		step := int(msg)
		if m.state != stStartup {
			break // power-down while sequence was in flight
		}
		if step >= len(startupSeq) {
			// All steps done — reset hardware, show POST OK for 2 seconds.
			m.seg7 = 0x3F // show "0"
			m.leds = [4]bool{}
			m.dips = [4]bool{}
			m.state = stPostTest
			if m.vpReady {
				m.viewport.SetContent(vpContent(&m))
			}
			cmds = append(cmds, tea.Tick(2*time.Second, func(_ time.Time) tea.Msg {
				return postTestDoneMsg{}
			}))
			break
		}
		// Apply this step and schedule the next tick after its delay.
		startupSeq[step].action(&m)
		cmds = append(cmds, startupTick(step+1, startupSeq[step].delay))

	// ── POST OK banner done ───────────────────────────────────────────────────
	case postTestDoneMsg:
		if m.state != stPostTest {
			break
		}
		m.state = stRunning
		if m.vpReady {
			m.viewport.SetContent(vpContent(&m))
			m.viewport.GotoBottom()
		}
		// Start PC polling to detect CPU running/halted.
		cmds = append(cmds,
			tea.Tick(1*time.Second, func(_ time.Time) tea.Msg { return pcPollTickMsg{} }),
			waitMonResp(m.mon.respCh),
		)

	// ── UART data ─────────────────────────────────────────────────────────────
	case uartDataMsg:
		// Silently collect UART data during startup/posttest so nothing is
		// lost; only push to the viewport once we're fully running.
		if m.state == stPoweredDown || m.state == stConnecting || m.state == stError {
			break
		}
		m.uartPartial += string(msg)
		for {
			idx := strings.IndexByte(m.uartPartial, '\n')
			if idx < 0 {
				break
			}
			line := strings.TrimRight(m.uartPartial[:idx], "\r")
			m.uartLines = append(m.uartLines, line)
			parseLEDState(&m, line)
			m.uartPartial = m.uartPartial[idx+1:]
		}
		// Only update the visible viewport when live — during startup/posttest
		// vpContent returns the static self-test banner instead.
		if m.vpReady && m.state == stRunning {
			m.viewport.SetContent(vpContent(&m))
			m.viewport.GotoBottom()
		}
		cmds = append(cmds, waitUART(m.uartCh))

	case uartErrMsg:
		// Ignore if we intentionally powered down.
		if m.state == stPoweredDown {
			break
		}
		m.state = stError
		m.errMsg = "Connection lost: " + msg.err.Error()

	// ── PC poll tick ──────────────────────────────────────────────────────────
	case pcPollTickMsg:
		if m.state != stRunning || m.mon == nil {
			break // stop polling when not running
		}
		cmds = append(cmds,
			m.mon.pollPC(),
			tea.Tick(1*time.Second, func(_ time.Time) tea.Msg { return pcPollTickMsg{} }),
		)

	// ── Monitor response (PC value) ───────────────────────────────────────────
	case monRespMsg:
		if m.state != stRunning || m.mon == nil {
			break
		}
		pc := string(msg)
		if pc == m.lastPC {
			m.pcSameCount++
			if m.pcSameCount >= 6 {
				m.cpuHalted = true
			}
		} else {
			m.lastPC = pc
			m.pcSameCount = 0
			m.cpuHalted = false
		}
		// Continue listening for the next response.
		cmds = append(cmds, waitMonResp(m.mon.respCh))
	}

	return m, tea.Batch(cmds...)
}

// ── View ──────────────────────────────────────────────────────────────────────

func (m model) View() string {
	if !m.vpReady {
		return "Initializing..."
	}
	return renderFrame(m)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// vpHeight calculates how many lines are available for the UART viewport.
// Fixed chrome = border(2) + title(1) + status(1) + divider(1) + board(7) +
//
//	divider(1) + uart-header(1) + divider(1) + divider(1) + cmdbar(2) = 18
//
// The stRunning cmd bar intentionally uses 2 lines to keep all bindings
// visible without wrapping on an 80-column terminal.
const fixedChrome = 18

func vpHeight(termH int) int {
	h := termH - fixedChrome
	if h < 3 {
		h = 3
	}
	return h
}

// parseLEDState updates m.leds by scanning UART lines for ON/OFF markers.
func parseLEDState(m *model, line string) {
	names := []string{"LED0", "LED1", "LED2", "LED3"}
	for i, name := range names {
		if strings.Contains(line, name+" ON") {
			m.leds[i] = true
		} else if strings.Contains(line, name+" OFF") {
			m.leds[i] = false
		}
	}
}

// vpContent builds the string for viewport.SetContent.
// During self-test and post-test it returns a static banner instead of UART
// data so the pane doesn't flicker with live firmware output.
func vpContent(m *model) string {
	switch m.state {
	case stStartup:
		return startupVPContent(m.viewport.Width, m.viewport.Height)
	case stPostTest:
		return postTestVPContent(m.viewport.Width, m.viewport.Height)
	}
	// Normal: hard-wrap UART lines to viewport width.
	w := m.viewport.Width
	var b strings.Builder
	for i, line := range m.uartLines {
		if i > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(hardWrap(line, w))
	}
	if m.uartPartial != "" {
		if len(m.uartLines) > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(hardWrap(m.uartPartial, w))
	}
	return b.String()
}

// hardWrap inserts newlines so no run between newlines exceeds w characters.
func hardWrap(s string, w int) string {
	if w <= 0 || len(s) <= w {
		return s
	}
	var b strings.Builder
	for len(s) > w {
		b.WriteString(s[:w])
		b.WriteByte('\n')
		s = s[w:]
	}
	b.WriteString(s)
	return b.String()
}
