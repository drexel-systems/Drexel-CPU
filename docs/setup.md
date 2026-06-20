# CS281 Dev Environment Setup

This guide covers everything you need to build and run the CS281 labs on macOS, Windows, and Linux (Ubuntu). VS Code is optional — the labs build and run entirely from the command line.

---

## What You Need

| Tool | Purpose |
|------|---------|
| **Renode** | RISC-V emulator that runs the virtual CS281 board |
| **RISC-V GNU Toolchain** | Cross-compiler and linker (`riscv64-elf-as`, `riscv64-elf-ld`, `riscv64-elf-gdb`) |
| **make** | Build system used by every lab |
| **telnet** | Connect to UART output and the Renode monitor |
| **VS Code** *(optional)* | Each lab includes a `.vscode/` folder with tasks, launch configs, and IntelliSense settings. Any editor works. |

---

## macOS

### 1. Homebrew
If you don't have Homebrew:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Xcode Command Line Tools (provides `make`)
```bash
xcode-select --install
```

### 3. RISC-V GNU Toolchain
```bash
brew install riscv-gnu-toolchain
```
This installs `riscv64-elf-as`, `riscv64-elf-ld`, `riscv64-elf-gcc`, `riscv64-elf-gdb`, and friends.

Verify:
```bash
riscv64-elf-as --version
```

### 4. Renode
```bash
brew install --cask renode
```
Or download the `.pkg` installer from [renode.io/get](https://renode.io/get/).

Verify:
```bash
renode --version
```

### 5. telnet
macOS no longer ships telnet by default:
```bash
brew install telnet
```

---

## Linux (Ubuntu 22.04 / 24.04)

### 1. System packages
```bash
sudo apt update
sudo apt install -y make telnet
```

### 2. RISC-V GNU Toolchain

Ubuntu's apt package uses the `riscv64-unknown-elf-*` prefix rather than `riscv64-elf-*`. The lab Makefiles default to `riscv64-elf`. You have two options:

**Option A — apt package + symlinks (quickest)**
```bash
sudo apt install -y gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf gdb-multiarch
```
Then create prefix aliases so `make` finds the tools:
```bash
for tool in as ld objdump objcopy; do
  sudo ln -sf /usr/bin/riscv64-unknown-elf-$tool /usr/local/bin/riscv64-elf-$tool
done
sudo ln -sf /usr/bin/gdb-multiarch /usr/local/bin/riscv64-elf-gdb
```

Verify:
```bash
riscv64-elf-as --version
```

**Option B — xPack RISC-V toolchain (uses `riscv64-elf-*` natively)**
```bash
# Install Node.js first (needed for xpm)
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

# Install xpm and the toolchain
sudo npm install -g xpm
xpm install -g @xpack-dev-tools/riscv-none-elf-gcc@latest
```
Then update the `CROSS` variable in each lab's Makefile from `riscv64-elf` to `riscv-none-elf`, or add the xPack bin directory to your PATH.

### 3. Renode
Download the latest `.deb` package from [github.com/renode/renode/releases](https://github.com/renode/renode/releases):
```bash
# Example for Renode 1.16 — check releases page for the current version
wget https://github.com/renode/renode/releases/download/v1.16.0/renode_1.16.0_amd64.deb
sudo dpkg -i renode_1.16.0_amd64.deb
sudo apt install -f   # fix any missing dependencies
```

Verify:
```bash
renode --version
```

---

## Windows

The recommended approach is **WSL2 (Windows Subsystem for Linux)** running Ubuntu. This gives you a full Linux environment where the Ubuntu instructions above apply exactly, without any toolchain compatibility issues.

### 1. Enable WSL2
Open PowerShell as Administrator:
```powershell
wsl --install
```
This installs WSL2 with Ubuntu. Restart when prompted.

### 2. Open Ubuntu and follow the Linux instructions
Once Ubuntu is running in WSL2, follow the **Linux (Ubuntu)** section above exactly. All tools — Renode, the toolchain, make, telnet — install the same way.

### 3. Networking
WSL2 forwards localhost ports to Windows automatically. When Renode opens UART on port 3456 and the monitor on port 1234 inside WSL2, you can connect to them from the same WSL2 terminal with `telnet localhost 3456` as normal.

### 4. VS Code (optional)
Install [VS Code for Windows](https://code.visualstudio.com/) and the [WSL extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl). Open a lab folder from within WSL2 with:
```bash
code .
```
VS Code connects to WSL2 automatically and the `.vscode/` configs in each lab will work as-is.

---

## Verifying Your Setup

From the repo root, run the Lab 1 smoke test:
```bash
cd lab1-blinky
make              # should produce build/lab1.elf with no errors
make run          # launches Renode — you should see "Starting emulation..."
```

In a second terminal:
```bash
cd lab1-blinky
make uart-connect # telnet to port 3456 — you should see "LED0 ON / LED0 OFF" output
```

If both work, your environment is fully set up.

---

## Troubleshooting

**`riscv64-elf-as: command not found`** — the toolchain isn't on your PATH. On macOS, try `brew link riscv-gnu-toolchain`. On Ubuntu, check that the symlinks in `/usr/local/bin` are correct.

**`renode: command not found`** — on macOS, Homebrew cask installs may need `/Applications/Renode.app/Contents/MacOS` on your PATH, or use the `renode` wrapper script the installer creates. On Ubuntu, the `.deb` install places `renode` at `/usr/bin/renode`.

**`telnet: connect to address 127.0.0.1: Connection refused`** — Renode hasn't started yet, or it crashed on startup. Check the `make run` terminal for error output.

**Port 1234 already in use** — another application (commonly VS Code) is holding port 1234. Quit and restart VS Code, then run `make run` again.
