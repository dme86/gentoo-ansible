# VM desktop integration validation

Tested on the existing Gentoo aarch64 guest with QEMU 10.2.4/Cocoa on macOS,
VirtIO GPU, Anvil commit `0fd22bc41071a5918fcfd164b3753ff2a9a4a25f`, and the
pinned Paprika source plus `patches/paprika-native-qemu.patch`.

| Check | Result |
| --- | --- |
| Physically drag the host window edge | Guest current/preferred mode changes from 512x320 to 768x480 |
| Terminal window follows the desktop | PTY changes from 50x14 to 75x22 cells |
| Host to guest, Unicode/multiline, no final newline | Exact 66-byte match |
| Guest to host, Unicode/multiline | Exact 91-byte match |
| Host to guest, larger text | Exact 159747-byte match |
| Guest to host, larger text | Exact 159770-byte match |
| Kill clipboard service main process | User manager reconnects automatically; NRestarts increments to 1 |
| Repeat all text transfers after reconnect | All exact matches pass again |
| Disable integration | User service stops and managed startup entry is removed |
| Re-enable with detected QEMU/KVM defaults | Port access and startup entry are restored |
| Repeat enabled deployment | Ansible reports changed=0, failed=0 |

The original macOS pasteboard items and their data types were privately saved
before text tests and restored afterward. Test output contains only controlled
payload sizes and equality results.

`make test-vm-integration` runs six launcher tests, including Apple's Bash 3.2,
and nine clipboard-session helper tests without reading the real clipboard.
The Paprika patch adds native-handshake and serial-ordering regressions;
its ordinary guest suite passed 70 tests, with all 14 SPICE tests repeated
after the final serial cleanup. External Sway/Xvfb tests remain optional.
Anvil's actual protocol client tests focus-preserving transfers through both
data-control protocols, normal and primary selection independence, replacement,
and clearing; the corresponding GitHub CI protocol matrix passes.

GUI test-tool modifier chords reached QEMU's raw keyboard as plain characters.
They therefore do not establish physical Ctrl+Shift+C/V behavior. The transfer
tests use real Wayland clipboard clients; rst's shortcut source and clipboard
serving lifetime were also checked. No speculative keyboard change was made.
UTM and image clipboard transport were not tested; the Cocoa bridge supports
UTF-8 text only.
