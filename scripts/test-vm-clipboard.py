#!/usr/bin/env python3
"""Check the session wrapper without a VM, systemd calls or clipboard access."""

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import socket
import tempfile
import unittest
from unittest import mock


HELPER = Path(__file__).with_name('anvil-vm-clipboard.py')
SPEC = importlib.util.spec_from_file_location('anvil_vm_clipboard', HELPER)
clipboard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(clipboard)


class AgentExecuted(Exception):
    """Stop at execve rather than replacing the test process with an agent."""


class ClipboardSessionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='vm-clipboard-', dir='/tmp')
        self.addCleanup(self.temporary.cleanup)
        self.runtime = Path(self.temporary.name)
        self.display = self.runtime / 'wayland-test'
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.addCleanup(self.listener.close)
        self.listener.bind(str(self.display))
        self.listener.listen(16)
        self.environment = {
            'XDG_RUNTIME_DIR': str(self.runtime),
            'WAYLAND_DISPLAY': self.display.name,
            'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/private/application/bus',
            'HOME': '/home/example',
            'PAPRIKA_VDAGENT_FILE_DIR': '/home/example/Downloads',
        }
        self.patch_environment = mock.patch.dict(os.environ, self.environment, clear=True)
        self.patch_environment.start()
        self.addCleanup(self.patch_environment.stop)
        self.patch_port = mock.patch.object(clipboard, 'PORT', Path('/dev/null'))
        self.patch_port.start()
        self.addCleanup(self.patch_port.stop)
        self.patch_stock = mock.patch.object(clipboard, 'stock_agent_running', return_value=False)
        self.stock = self.patch_stock.start()
        self.addCleanup(self.patch_stock.stop)
        self.patch_exec = mock.patch.object(clipboard.os, 'execve', side_effect=AgentExecuted)
        self.execute = self.patch_exec.start()
        self.addCleanup(self.patch_exec.stop)

    def test_startup_uses_scoped_session_helper_and_systemd_user_bus(self):
        with self.assertRaises(AgentExecuted):
            clipboard.main([])
        binary, arguments, environment = self.execute.call_args.args
        self.assertEqual(binary, clipboard.AGENT)
        self.assertEqual(arguments, [binary, '--backend', 'wayland', 'session-start'])
        self.assertEqual(environment['DBUS_SESSION_BUS_ADDRESS'],
                         f'unix:path={self.runtime}/bus')
        self.assertEqual(environment['WAYLAND_DISPLAY'], self.display.name)
        self.assertEqual(environment['XDG_RUNTIME_DIR'], str(self.runtime))
        self.assertEqual(environment['HOME'], '/home/example')
        self.assertEqual(dict(os.environ), self.environment)

    def test_service_executes_only_wayland_agent_with_file_transfers_disabled(self):
        with self.assertRaises(AgentExecuted):
            clipboard.main(['--run'])
        binary, arguments, environment = self.execute.call_args.args
        self.assertEqual(arguments, [binary, '--backend', 'wayland', '--virtio-port', '/dev/null'])
        self.assertNotIn('HOME', environment)
        self.assertNotIn('PAPRIKA_VDAGENT_FILE_DIR', environment)
        self.assertEqual(environment['WAYLAND_DISPLAY'], self.display.name)
        self.assertEqual(environment['XDG_RUNTIME_DIR'], str(self.runtime))
        self.assertEqual(dict(os.environ), self.environment)

    def test_missing_or_regular_port_is_a_quiet_noop(self):
        port = self.runtime / 'missing-port'
        with mock.patch.object(clipboard, 'PORT', port):
            output = io.StringIO()
            with contextlib.redirect_stderr(output), contextlib.redirect_stdout(output):
                self.assertEqual(clipboard.main([]), 0)
                port.write_text('not a virtio character device')
                self.assertEqual(clipboard.main(['--run']), 0)
            self.assertEqual(output.getvalue(), '')
        self.execute.assert_not_called()

    def test_inaccessible_port_does_not_start_an_agent(self):
        with mock.patch.object(clipboard.os, 'access', return_value=False):
            self.assertEqual(clipboard.main([]), 0)
        self.execute.assert_not_called()

    def test_logout_with_a_stale_wayland_socket_stops_retries(self):
        self.listener.close()
        self.assertTrue(self.display.exists())
        self.assertEqual(clipboard.main(['--run']), 0)
        self.execute.assert_not_called()

    def test_absolute_wayland_socket_is_supported(self):
        os.environ['WAYLAND_DISPLAY'] = str(self.display)
        with self.assertRaises(AgentExecuted):
            clipboard.main(['--run'])
        self.assertEqual(self.execute.call_args.args[2]['WAYLAND_DISPLAY'], str(self.display))

    def test_missing_session_environment_does_not_launch_or_create_a_manager(self):
        for values in ({}, {'XDG_RUNTIME_DIR': 'relative', 'WAYLAND_DISPLAY': self.display.name},
                       {'XDG_RUNTIME_DIR': str(self.runtime)}):
            with self.subTest(environment=values), mock.patch.dict(os.environ, values, clear=True):
                self.assertEqual(clipboard.main([]), 0)
        self.execute.assert_not_called()

    def test_stock_agents_are_refused_instead_of_competing_for_the_port(self):
        self.stock.return_value = True
        output = io.StringIO()
        with contextlib.redirect_stderr(output):
            self.assertEqual(clipboard.main([]), 1)
        self.assertIn('stop the stock SPICE agents', output.getvalue())
        self.execute.assert_not_called()

    def test_invalid_arguments_cannot_be_forwarded_to_the_agent(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(clipboard.main(['--file-dir', '/tmp/downloads']), 2)
        self.execute.assert_not_called()


if __name__ == '__main__':
    unittest.main()
