# Paprika native-QEMU compatibility

`paprika-native-qemu.patch` applies to
[Paprika v0.2.1](https://github.com/thelicato/paprika-vdagent/tree/c65de8829ad126997f868c3cab9c00d6dab90023),
commit `c65de8829ad126997f868c3cab9c00d6dab90023`.
The upstream code and this patch are licensed GPL-3.0-only; see
[`PAPRIKA-LICENSE`](PAPRIKA-LICENSE). Upstream's `LICENSE` also remains in the
checked-out source and its build worktree.

The patch addresses two failures observed with QEMU 10.2.4's built-in
`qemu-vdagent` backend:

- With `PAPRIKA_VDAGENT_QEMU_NATIVE=1`, answer QEMU's initial capabilities request
  once. An unsolicited announcement followed by another reply resets an already
  registered peer and disconnects the guest. Publish clipboard readiness only
  after the reply is written, including for initial clipboard snapshots.
- Track serial ordering independently for regular and primary selections.
  Accept host ties and advance subsequent guest serials after a host update.
  The original ordering caused repeated host/guest ownership changes to be
  silently discarded.

Without the flag, regular SPICE keeps its existing guest-initiated handshake.
Set `vm_clipboard_native_qemu=false` when using that transport, including UTM.

Ansible keeps the pinned upstream checkout unchanged, applies this patch in a
worktree keyed by revision and patch content, and uses a separate managed Cargo
cache. Every run lets Cargo validate the selected source before installation.
Interrupted patch application is recovered by checking the reverse patch before
writing the completion marker.

The patch includes socket-pair tests for capability ordering, concurrent initial
clipboard reads, the original disconnect, and repeated QEMU-style ownership
changes. The guest suite passed 70 ordinary tests; all 14 SPICE tests passed
again after the final serial cleanup. External Sway/Xvfb tests remain optional.
