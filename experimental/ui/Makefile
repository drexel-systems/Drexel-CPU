BINARY  := cs281ui
BINDIR  := bin

.PHONY: all run tidy clean \
        mac-arm64 mac-amd64 linux-amd64 linux-arm64 windows-amd64

# Build native binary for the current machine
build: tidy
	go build -o $(BINARY) .

# Run without building a binary (dev mode)
run:
	go run .

# Fetch/update dependencies and generate go.sum
tidy:
	go mod tidy

# Cross-compile for every supported platform
all: tidy mac-arm64 mac-amd64 linux-amd64 linux-arm64 windows-amd64

$(BINDIR):
	mkdir -p $(BINDIR)

mac-arm64: $(BINDIR)
	GOOS=darwin  GOARCH=arm64 go build -o $(BINDIR)/$(BINARY)-mac-arm64     .

mac-amd64: $(BINDIR)
	GOOS=darwin  GOARCH=amd64 go build -o $(BINDIR)/$(BINARY)-mac-amd64     .

linux-amd64: $(BINDIR)
	GOOS=linux   GOARCH=amd64 go build -o $(BINDIR)/$(BINARY)-linux-amd64   .

linux-arm64: $(BINDIR)
	GOOS=linux   GOARCH=arm64 go build -o $(BINDIR)/$(BINARY)-linux-arm64   .

windows-amd64: $(BINDIR)
	GOOS=windows GOARCH=amd64 go build -o $(BINDIR)/$(BINARY)-windows-amd64.exe .

clean:
	rm -rf $(BINDIR) $(BINARY)
