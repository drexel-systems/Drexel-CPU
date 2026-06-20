package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	monPort  := flag.Int("monitor-port", 1234, "Renode monitor port")
	uartPort := flag.Int("uart-port",    3456, "UART output port")
	flag.Parse()

	p := tea.NewProgram(
		newModel(*monPort, *uartPort),
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
