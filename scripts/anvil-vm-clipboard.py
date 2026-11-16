#!/usr/bin/env python3
"""Start one text-only VM clipboard bridge in the current Anvil session."""

import os
from pathlib import Path
import socket
import stat
import sys


PORT = Path('/dev/virtio-ports/com.redhat.spice.0')
AGENT = '/usr/local/bin/paprika-vdagent'


def session_ready(environment):
    """Absent channels and exited sessions are ordinary, quiet no-op cases."""
    try:
        if not stat.S_ISCHR(PORT.stat().st_mode):
            return False
    except OSError:
        return False
    if not os.access(PORT, os.R_OK | os.W_OK):
        return False
    runtime = environment.get('XDG_RUNTIME_DIR', '')
    display = environment.get('WAYLAND_DISPLAY', '')
    if not runtime or not Path(runtime).is_absolute() or not display:
        return False
    path = Path(display) if Path(display).is_absolute() else Path(runtime) / display
    # The file may survive a crashed compositor. Check the listener so service
    # retries stop after logout even when a stale socket inode remains.
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(0.5)
            connection.connect(str(path))
    except OSError:
        return False
    return True


def stock_agent_running():
    for process in Path('/proc').glob('[0-9]*/comm'):
        try:
            if process.read_text().strip() in ('spice-vdagent', 'spice-vdagentd'):
                return True
        except OSError:
            continue
    return False


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    if arguments not in ([], ['--run']):
        print('usage: anvil-vm-clipboard [--run]', file=sys.stderr)
        return 2
    environment = os.environ.copy()
    if not session_ready(environment):
        return 0
    if stock_agent_running():
        print('anvil-vm-clipboard: stop the stock SPICE agents before using Paprika', file=sys.stderr)
        return 1
    if arguments == ['--run']:
        # Pinned Paprika disables incoming files when neither a file-dir nor
        # HOME is supplied. Restrict this bridge to clipboard text; keep the
        # parent desktop's environment and home directory unchanged.
        environment.pop('HOME', None)
        environment.pop('PAPRIKA_VDAGENT_FILE_DIR', None)
        command = [AGENT, '--backend', 'wayland', '--virtio-port', str(PORT)]
    else:
        # start-anvil uses dbus-run-session. systemctl --user must reach the
        # systemd user manager rather than that private application bus.
        environment['DBUS_SESSION_BUS_ADDRESS'] = 'unix:path=' + environment['XDG_RUNTIME_DIR'] + '/bus'
        # Upstream session-start writes this service's private runtime drop-in
        # systemd/user/paprika-vdagent.service.d/90-paprika-session.conf, including
        # WAYLAND_DISPLAY/XDG_RUNTIME_DIR, then daemon-reloads and restarts it.
        command = [AGENT, '--backend', 'wayland', 'session-start']
    os.execve(AGENT, command, environment)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
