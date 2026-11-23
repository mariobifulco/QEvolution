# QEvolution

QEvolution is a Godot game for building circuits with one to four qubits and exploring how the quantum state changes after each operation. It includes a free lab, example circuits, and three challenges about entanglement.

## Play

Open `project.godot` in Godot 4.6 or later and press **F6** from the main scene or **F5** from anywhere in the editor.

1. Start with a Hadamard gate on one wire. Use **Add qubit** to expand the circuit up to four qubits or **Remove qubit** to choose a wire to remove. Removing a wire deletes the gates that act on it. Joint measurements keep their remaining wires. Use **Undo** to restore the previous circuit.
2. Drag a gate from the palette onto a wire, or select a gate and click a slot. For **CX**, pick the control wire first and the target second. **RZZ** also takes two wires. Drag placed gates to change their step or wires. Select a gate and press **Delete** to remove it. The rotation field uses degrees.
3. Select **Run circuit** and use **Next**, **Back**, or **Play**. The 3D state and probability histogram update together at each step. Playback pauses at measurements. **New run** starts over and draws new samples.
4. Drag the 3D view to orbit and scroll to zoom. Use **Focus** to inspect a single Bloch sphere. With four qubits, the view menu also offers the three two-versus-two cuts.
5. Try a challenge or open an example such as **GHZ₄** to see how the display distinguishes pair entanglement from genuine four-way entanglement.

### OpenXR

On a PC with an active OpenXR runtime and a connected headset, launch from the project directory:

```sh
godot --path . --rendering-method mobile --rendering-driver vulkan --xr-mode on
```

Aim either controller at the workbench and pull the trigger. Select gates and slots with the pointer, and use the thumbstick left or right to scroll long circuits. The 3D processor stands beside the workbench. The OpenQASM panel accepts the system clipboard or input from a keyboard connected to the PC. When a headset session cannot start, the game opens the desktop lab. [Godot OpenXR settings](https://docs.godotengine.org/en/stable/tutorials/xr/openxr_settings.html)

## OpenQASM 3.0

Select **OpenQASM** to copy the current program or paste and validate a new one. The importer accepts one to four logical qubits, up to 256 operations after broadcast, `stdgates.inc`, and the gates `h`, `x`, `y`, `z`, `rx`, `ry`, `rz`, `cx`, and `rzz`. Rotation angles are in radians and can use numeric literals, `pi`, `tau`, `euler`, parentheses, and basic arithmetic. RZZ is built into the lab. Programs containing RZZ are exported with its CX–RZ–CX definition.

```qasm
OPENQASM 3.0;
include "stdgates.inc";
qubit[4] q;
bit[4] result;

h q[0];
cx q[0], q[1];
cx q[0], q[2];
cx q[0], q[3];
result = measure q;
```

Both assignment and arrow measurement syntax work. The lab validates classical destinations and displays the measured qubits in operand order. Import and export preserve the circuit's declared qubit count. Unsupported instructions such as classical control flow and arbitrary gate definitions report a line number. [OpenQASM 3.0 specification](https://openqasm.com/versions/3.0/)

## Read the QPU

| Part | What it shows |
| --- | --- |
| Bloch spheres | Reduced state of each qubit. A shorter vector means greater entanglement with the rest of the pure state. |
| Edges | Pairwise concurrence. Every physical link stays visible. |
| Tetrahedron faces | Entanglement entropy between the opposite qubit and the other three. |
| Internal sections | Entanglement entropy across AB \| CD, AC \| BD, and AD \| BC, up to two bits. |
| Core | Minimum entropy across the seven cuts. A positive minimum indicates genuine four-qubit entanglement in the pure state. |

The histogram shows the computational-basis probabilities of the current state, with bits in circuit wire order. After measurement it shows the collapsed state. The gold measurement caption gives the sampled outcome and its probability before collapse. Hover over the caption for the full pre-measurement distribution. Stepping back and forward retains the same sample. [Wootters’ concurrence formula](https://doi.org/10.1103/PhysRevLett.80.2245)

## Verify

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/check_lab.gd
```

The checks cover interference, rotations, Bell and GHZ states, measurement and replay, OpenQASM validation and round trips, and the headset panel with simulated tracking and controller input.
