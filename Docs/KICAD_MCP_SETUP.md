# KiCad MCP Server Setup & Usage Guide

## Overview

The KiCad MCP (Model Context Protocol) Server connects AI assistants with KiCad 9.0+ / 10.0+ to inspect schematics, trace netlists, perform Design Rule Checks (DRC), Electrical Rule Checks (ERC), export production files (Gerbers, drill, PDF, SVG, 3D renderings), and generate embedded device trees.

- **Server Package**: `kicad-mcp-server` (Seeed Studio)
- **License**: MIT (Free for commercial use)
- **KiCad Version**: KiCad 10.0.6 (installed at `/Applications/KiCad/KiCad.app`)
- **CLI Executable**: `/opt/homebrew/bin/kicad-cli` (symlinked from KiCad app bundle)
- **MCP Server Binary**: `/Users/ngkarchai/.local/bin/kicad-mcp-server`
- **Configuration File**: `~/.gemini/config/mcp_config.json`

---

## Configuration

The server is globally configured in `~/.gemini/config/mcp_config.json`:

```json
{
  "mcpServers": {
    "notebooklm": {
      "command": "/opt/homebrew/bin/npx",
      "args": [
        "-y",
        "@charlie.act7/gemini-notebook-mcp"
      ]
    },
    "kicad": {
      "command": "/Users/ngkarchai/.local/bin/kicad-mcp-server",
      "args": [],
      "env": {
        "PATH": "/Applications/KiCad/KiCad.app/Contents/MacOS:/opt/homebrew/bin:/Users/ngkarchai/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      }
    }
  }
}
```

---

## Available MCP Tools (47 Tools)

### 1. Project Management
- `create_kicad_project`: Create new KiCad 9.0+ / 10.0+ projects from official templates (e.g. Arduino, Raspberry Pi Hat, etc.).

### 2. Schematic Analysis & Editing
- `list_schematic_components`: List all components in a `.kicad_sch` file with references and values.
- `list_schematic_nets`: List all electrical nets in the schematic.
- `get_schematic_info`: Overview of schematic sheets, title block, and hierarchy.
- `get_symbol_details`: Detailed pinout and properties of a specific symbol.
- `search_symbols`: Search KiCad symbol libraries.
- `search_components_by_type`: Filter components by category (resistors, capacitors, ICs).
- `add_component_from_library`: Add component to schematic.
- `add_wire`: Connect schematic pins/nodes with wires.
- `add_label`: Place net labels.
- `add_global_label` & `add_hierarchical_label`: Place global and sheet labels.

### 3. Netlist Tracing
- `generate_netlist`: Generate XML netlist using `kicad-cli`.
- `trace_netlist_connection`: Pin-accurate tracing between components.
- `get_netlist_nets`: Extract net names from generated netlist.
- `get_netlist_components`: Extract pin connections from netlist.

### 4. PCB Layout & Inspection
- `list_pcb_footprints`: List placed footprints with coordinates, layers, and orientations.
- `get_pcb_statistics`: Track counts, board dimensions, layer stackup, via statistics.
- `analyze_pcb_nets`: Inspect routing status and net topologies.
- `find_tracks_by_net`: Locate tracks and vias associated with a specific net.
- `setup_pcb_layout`: Set board boundary dimensions and layer configurations.
- `analyze_pcb_signal_integrity`: High-speed trace inspection and differential pairs.
- `analyze_pcb_power_integrity`: Power plane and ground net clearance checks.

### 5. Validation & Rules Checks
- `run_erc`: Run Electrical Rules Check on schematics via headless `kicad-cli`.
- `run_drc`: Run Design Rules Check on PCBs via headless `kicad-cli`.
- `get_erc_violations`: Retrieve ERC errors and warnings.
- `get_drc_violations`: Retrieve DRC clearance and track errors.
- `export_erc_report` & `export_drc_report`: Generate validation reports.

### 6. Export & Visualization
- `export_gerber`: Export production Gerber and drill files.
- `render_pcb`: Render 3D board view to PNG/JPEG images via `kicad-cli pcb render`.
- `export_pcb_3d`: Export 3D STEP/VRML models.
- `export_schematic_svg`: Export schematic pages to SVG.

### 7. Hardware & Embedded Code Generation
- `generate_device_tree`: Generate Linux Device Tree (`.dts`) from schematic.
- `extract_gpio_config`: Extract GPIO mappings.
- `extract_i2c_devices` & `extract_spi_devices`: Auto-detect peripherals on shared buses.
- `extract_power_domains`: Detect VCC/3V3/1V8 power rails.
- `analyze_pin_functions`: Analyze pin multiplexing capabilities.
- `detect_pin_conflicts`: Detect overlapping pin assignments.

### 8. Parts Registry
- `search_parts_registry`: Search 21,000+ verified components on PartReel.
- `get_registry_part`: Get footprint and 3D model metadata.
- `download_registry_part`: Download verified symbols/footprints directly into project.

---

## Verification

To verify in this environment:
1. The server runs via `/Users/ngkarchai/.local/bin/kicad-mcp-server`.
2. Initialized successfully with protocol version `2024-11-05`.
3. Tested `create_kicad_project` and confirmed full compatibility with KiCad 10.0.6.
