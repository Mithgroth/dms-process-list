# Process List (DMS Desktop Plugin)

Desktop widget for DankMaterialShell that shows running processes with live CPU/memory data.

## Features

- Live process list from `ps`
- CPU values normalized by core count
- Sorting by process name, count, CPU, memory, and PID
- Grouping by process command (singletons stay as normal rows)
- Expand/collapse grouped processes
- Scope filter: `ALL | USER | SYSTEM` (default: `USER`)
- Toggle to hide idle processes
- Process name color coding:
  - User processes: accent color
  - System processes: gray
  - Mixed groups: default text color
- USER/SYSTEM split is based on `UID_MIN` from `/etc/login.defs` (fallback: `1000`)

## Requirements

- DankMaterialShell with desktop plugin support (`>=0.1.18`)
- `ps` (from `procps`)
- `getconf` (usually from `glibc`)

## Installation

### Option 1: Git clone

```bash
cd ~/.config/DankMaterialShell/plugins
git clone https://github.com/Mithgroth/dms-process-list.git processList
dms restart
```

### Option 2: Release tarball

```bash
mkdir -p ~/.config/DankMaterialShell/plugins
tar -xzf processList-1.2.1.tar.gz -C ~/.config/DankMaterialShell/plugins
dms restart
```

Then enable `Process List` in `Settings -> Plugins`, and add it from `Desktop Widgets`.

## Usage

- Click column headers to sort.
- Click `ALL`, `USER`, or `SYSTEM` to switch scope.
- Click `IDLE:ON/OFF` to toggle idle filtering.
- Click grouped rows (`[+]` / `[-]`) to expand or collapse.

## Packaging

Create a release archive from this directory:

```bash
./package.sh
```

This writes `dist/processList-<version>.tar.gz`.
