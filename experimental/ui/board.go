package main

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// ── Colour palette ────────────────────────────────────────────────────────────

var (
	clrGold    = lipgloss.Color("#FFD700")
	clrBlue    = lipgloss.Color("#4A9EFF")
	clrAmber   = lipgloss.Color("#FF8C00") // 7-seg on  (amber, like real hardware)
	clrDimAmb  = lipgloss.Color("#2A1500") // 7-seg off
	clrDipOn   = lipgloss.Color("#4CAF50")
	clrDipOff  = lipgloss.Color("#555555")
	clrBorder  = lipgloss.Color("#4A9EFF")
	clrRunning = lipgloss.Color("#39FF14")
	clrOff     = lipgloss.Color("#666666")
	clrErr     = lipgloss.Color("#FF4444")
	clrConn    = lipgloss.Color("#4A9EFF")
	clrSubtle  = lipgloss.Color("#555555")
	clrKey     = lipgloss.Color("#FFD700")
	clrUART    = lipgloss.Color("#D0D0D0")
	clrSection = lipgloss.Color("#4A9EFF")

	// Per-LED colours: ON and dim-OFF variants
	ledOnColors = [4]lipgloss.Color{
		lipgloss.Color("#39FF14"), // LED0 — neon green
		lipgloss.Color("#FF4444"), // LED1 — red
		lipgloss.Color("#FFD700"), // LED2 — yellow
		lipgloss.Color("#4A9EFF"), // LED3 — blue
	}
	ledOffColors = [4]lipgloss.Color{
		lipgloss.Color("#0D2B0D"), // LED0 off
		lipgloss.Color("#2B0D0D"), // LED1 off
		lipgloss.Color("#2B2300"), // LED2 off
		lipgloss.Color("#0D1A2B"), // LED3 off
	}
)

// ledSt returns the appropriate style for LED i given its on/off state.
func ledSt(i int, on bool) lipgloss.Style {
	if on {
		return lipgloss.NewStyle().Foreground(ledOnColors[i])
	}
	return lipgloss.NewStyle().Foreground(ledOffColors[i])
}

// ── Styles ────────────────────────────────────────────────────────────────────

var (
	outerStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(clrBorder)

	titleSt   = lipgloss.NewStyle().Foreground(clrGold).Bold(true)
	sectionSt = lipgloss.NewStyle().Foreground(clrSection).Bold(true)
	subtleSt  = lipgloss.NewStyle().Foreground(clrSubtle)
	keySt     = lipgloss.NewStyle().Foreground(clrKey).Bold(true)
	errSt     = lipgloss.NewStyle().Foreground(clrErr).Bold(true)

	seg7OnSt  = lipgloss.NewStyle().Foreground(clrAmber)
	seg7OffSt = lipgloss.NewStyle().Foreground(clrDimAmb)

	dipOnSt  = lipgloss.NewStyle().Foreground(clrDipOn)
	dipOffSt = lipgloss.NewStyle().Foreground(clrDipOff)

	runningSt    = lipgloss.NewStyle().Foreground(clrRunning).Bold(true)
	startupSt    = lipgloss.NewStyle().Foreground(clrGold).Bold(true)
	poweredOffSt = lipgloss.NewStyle().Foreground(clrOff)
	connectingSt = lipgloss.NewStyle().Foreground(clrConn)
)

// ── Column widths ─────────────────────────────────────────────────────────────

const (
	colInputs = 26
	colSeg7   = 13
	// colLEDs = innerW - colInputs - colSeg7 - 2 (dividers)
)

// ── Top-level frame ───────────────────────────────────────────────────────────

func renderFrame(m model) string {
	iw := m.width - 2 // inner width: border takes 1 char each side
	if iw < 60 {
		iw = 60
	}

	var b strings.Builder

	// Title + status
	b.WriteString(center(titleSt.Render("CS281 Virtual Development Board"), iw) + "\n")
	b.WriteString(center(renderStatus(m), iw) + "\n")
	b.WriteString(subtleSt.Render(strings.Repeat("─", iw)) + "\n")

	// Hardware row
	for _, row := range renderBoardRows(m, iw) {
		b.WriteString(row + "\n")
	}
	b.WriteString(subtleSt.Render(strings.Repeat("─", iw)) + "\n")

	// UART output pane
	uartHdr := sectionSt.Render("  UART OUTPUT") +
		"  " + subtleSt.Render("↑↓ / j k / mouse scroll")
	b.WriteString(uartHdr + "\n")
	b.WriteString(subtleSt.Render(strings.Repeat("─", iw)) + "\n")

	if m.vpReady {
		b.WriteString(m.viewport.View() + "\n")
	}

	b.WriteString(subtleSt.Render(strings.Repeat("─", iw)) + "\n")

	// Command bar
	b.WriteString(renderCmdBar(m, iw) + "\n")

	return outerStyle.Width(iw).Render(b.String())
}

// ── Status line ───────────────────────────────────────────────────────────────

func renderStatus(m model) string {
	switch m.state {
	case stPoweredDown:
		return poweredOffSt.Render("◉  POWERED DOWN")
	case stConnecting:
		return connectingSt.Render("◌  CONNECTING…")
	case stStartup:
		return startupSt.Render("◈  SELF-TEST")
	case stPostTest:
		return runningSt.Render("✓  POST OK")
	case stRunning:
		return runningSt.Render("◉  RUNNING")
	case stError:
		return errSt.Render("✕  ERROR")
	}
	return ""
}

// ── Board hardware row ────────────────────────────────────────────────────────

// renderBoardRows produces 7 fixed-height rows showing inputs, 7-seg, and LEDs
// side-by-side, separated by │ dividers.
func renderBoardRows(m model, iw int) []string {
	ledsW := iw - colInputs - colSeg7 - 2 // 2 = two │ dividers
	if ledsW < 18 {
		ledsW = 18
	}

	inputs := buildInputsCol(m)
	seg7   := buildSeg7Col(m.seg7)
	leds   := buildLEDsCol(m)

	div := subtleSt.Render("│")
	rows := make([]string, 7)
	for i := range rows {
		ic := col(safeGet(inputs, i), colInputs)
		sc := center(safeGet(seg7, i), colSeg7)
		lc := col(safeGet(leds, i), ledsW)
		rows[i] = ic + div + sc + div + lc
	}
	return rows
}

// ── Inputs column ─────────────────────────────────────────────────────────────

func buildInputsCol(m model) []string {
	active := m.state == stRunning
	key := func(k string) string {
		if active {
			return keySt.Render(k)
		}
		return subtleSt.Render(k)
	}

	return []string{
		sectionSt.Render("  INPUTS"),
		"",
		fmt.Sprintf("  %s BTN0   %s", key("[0]"), subtleSt.Render("momentary")),
		fmt.Sprintf("  %s BTN1   %s", key("[1]"), subtleSt.Render("momentary")),
		fmt.Sprintf("  %s DIP0   %s", key("[2]"), renderDIP(m.dips[0])),
		fmt.Sprintf("  %s DIP1   %s", key("[3]"), renderDIP(m.dips[1])),
		"",
	}
}

// ── 7-segment column ──────────────────────────────────────────────────────────

func buildSeg7Col(bm byte) []string {
	lines := []string{sectionSt.Render(" 7-SEG")}
	lines = append(lines, renderSeg7(bm)...)
	lines = append(lines, renderDP(bm))
	return lines
}

// renderSeg7 returns 5 lines representing the 7 segments.
//
// Bit layout (matches cs281.inc / cs281_board.repl):
//
//	bit 0 = a  top          bit 4 = e  bottom-left
//	bit 1 = b  top-right    bit 5 = f  top-left
//	bit 2 = c  bottom-right bit 6 = g  middle
//	bit 3 = d  bottom       bit 7 = dp decimal point
func renderSeg7(bm byte) []string {
	seg := func(bit byte) bool { return bm&bit != 0 }

	horiz := func(bit byte) string {
		if seg(bit) {
			return seg7OnSt.Render("───")
		}
		return seg7OffSt.Render("───")
	}
	vertL := func(bit byte) string {
		if seg(bit) {
			return seg7OnSt.Render("█")
		}
		return seg7OffSt.Render("▏")
	}
	vertR := func(bit byte) string {
		if seg(bit) {
			return seg7OnSt.Render("█")
		}
		return seg7OffSt.Render("▕")
	}

	return []string{
		" " + horiz(0x01) + " ",         // a — top
		vertL(0x20) + "   " + vertR(0x02), // f — top-left, b — top-right
		" " + horiz(0x40) + " ",         // g — middle
		vertL(0x10) + "   " + vertR(0x04), // e — bottom-left, c — bottom-right
		" " + horiz(0x08) + " ",         // d — bottom
	}
}

func renderDP(bm byte) string {
	if bm&0x80 != 0 {
		return "      " + seg7OnSt.Render("•")
	}
	return "      " + seg7OffSt.Render("•")
}

// ── LEDs column ───────────────────────────────────────────────────────────────

func buildLEDsCol(m model) []string {
	l := func(i int) string {
		return ledSt(i, m.leds[i]).Render("⬤")
	}
	label := func(i int, name string) string {
		return ledSt(i, m.leds[i]).Render(name)
	}

	return []string{
		sectionSt.Render("  LEDs"),
		"",
		fmt.Sprintf("  %s %s    %s %s", l(0), label(0, "LED0"), l(1), label(1, "LED1")),
		fmt.Sprintf("  %s %s    %s %s", l(2), label(2, "LED2"), l(3), label(3, "LED3")),
		"",
		"",
		"",
	}
}

// ── DIP switch indicator ──────────────────────────────────────────────────────

func renderDIP(on bool) string {
	if on {
		return dipOnSt.Render("▲ ON ")
	}
	return dipOffSt.Render("▽ off")
}

// ── Command bar ───────────────────────────────────────────────────────────────

func renderCmdBar(m model, iw int) string {
	var parts string
	switch m.state {
	case stPoweredDown:
		parts = keySt.Render("[P]") + " Power Up" +
			"    " + keySt.Render("[Q]") + " Quit"

	case stConnecting:
		parts = connectingSt.Render("Connecting to Renode…") +
			"    " + keySt.Render("[Q]") + " Quit"

	case stStartup:
		parts = startupSt.Render("Self-test in progress…") +
			"    " + keySt.Render("[P]") + " Power Down" +
			"    " + keySt.Render("[Q]") + " Quit"

	case stPostTest:
		parts = runningSt.Render("Power On Self Test OK") +
			"    " + keySt.Render("[Q]") + " Quit"

	case stRunning:
		parts = keySt.Render("[0]") + " BTN0  " +
			keySt.Render("[1]") + " BTN1  " +
			keySt.Render("[2]") + " DIP0  " +
			keySt.Render("[3]") + " DIP1" +
			"    " + keySt.Render("[P]") + " Power Down" +
			"    " + keySt.Render("[Q]") + " Quit"

	case stError:
		// Wrap error message, then retry/quit
		parts = errSt.Render("⚠  "+m.errMsg) +
			"\n  " + keySt.Render("[P]") + " Retry    " +
			keySt.Render("[Q]") + " Quit"
	}

	_ = iw // reserved for future centering / truncation
	return "  " + parts
}

// ── Self-test viewport banners ────────────────────────────────────────────────

// startupVPContent returns the static text shown in the UART pane while the
// self-test animation is running. Real UART data is buffered behind the scenes.
func startupVPContent(w, h int) string {
	pad := h/2 - 2
	if pad < 1 {
		pad = 1
	}
	lines := make([]string, 0, pad+4)
	for i := 0; i < pad; i++ {
		lines = append(lines, "")
	}
	lines = append(lines,
		center(startupSt.Render("◈  Power On Self Test"), w),
		"",
		center(subtleSt.Render("Testing Board..."), w),
	)
	return strings.Join(lines, "\n")
}

// postTestVPContent returns the static text shown for 2 seconds after the
// self-test completes.
func postTestVPContent(w, h int) string {
	pad := h/2 - 1
	if pad < 1 {
		pad = 1
	}
	lines := make([]string, 0, pad+2)
	for i := 0; i < pad; i++ {
		lines = append(lines, "")
	}
	lines = append(lines,
		center(runningSt.Render("✓  Power On Self Test OK"), w),
	)
	return strings.Join(lines, "\n")
}

// ── Layout helpers ────────────────────────────────────────────────────────────

// col pads/truncates s to exactly w visible characters.
func col(s string, w int) string {
	return lipgloss.NewStyle().Width(w).MaxWidth(w).Render(s)
}

// center centres s (may contain ANSI codes) within w visible characters.
func center(s string, w int) string {
	return lipgloss.PlaceHorizontal(w, lipgloss.Center, s)
}

// safeGet returns lines[i] or "" when i is out of range.
func safeGet(lines []string, i int) string {
	if i < len(lines) {
		return lines[i]
	}
	return ""
}
