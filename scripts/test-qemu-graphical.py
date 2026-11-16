#!/usr/bin/env python3
"""Check graphical launcher arguments without starting a VM or touching its disk."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().with_name('qemu-graphical.sh')


class GraphicalLauncher(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='gentoo-launcher-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.disk = self.root / 'existing disk.qcow2'
        self.disk.touch()
        self.firmware = self.root / 'firmware.fd'
        self.firmware.touch()
        self.log = self.root / 'argv.json'
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        QEMU_EFI=str(self.firmware), FAKE_LOG=str(self.log),
                        FAKE_ARCH='arm64', FAKE_SYSTEM='Darwin', VM_CLIPBOARD='1',
                        SSH_PORT='2244')
        self.env.pop('QEMU_DISPLAY', None)
        (self.bin / 'uname').write_text(
            '#!/bin/sh\ncase "$1" in\n'
            '-m) echo "$FAKE_ARCH";;\n-s) echo "$FAKE_SYSTEM";;\nesac\n')
        qemu = f'#!{sys.executable}\n' + '''import json, os, sys
if sys.argv[-2:] == ['-chardev', 'help']:
    print('  qemu-vdagent' if os.environ.get('FAKE_NO_AGENT') != '1' else '  stdio')
else:
    with open(os.environ['FAKE_LOG'], 'w') as stream:
        json.dump(sys.argv[1:], stream)
'''
        for name in ('qemu-system-aarch64', 'qemu-system-x86_64'):
            (self.bin / name).write_text(qemu)
        for path in self.bin.iterdir():
            path.chmod(0o755)

    def run_launcher(self, **environment):
        env = dict(self.env, **environment)
        # Exercise Apple's Bash 3.2 as well as the caller's newer Bash on macOS.
        return subprocess.run(['/bin/bash', str(SCRIPT), str(self.disk)],
                              env=env, capture_output=True, text=True)

    def arguments(self, **environment):
        result = self.run_launcher(**environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(self.log.read_text())

    def test_macos_resize_clipboard_and_existing_devices(self):
        args = self.arguments()
        self.assertEqual(args[args.index('-display') + 1], 'cocoa,zoom-to-fit=on')
        self.assertIn('qemu-vdagent,id=clipboard,clipboard=on,mouse=off', args)
        self.assertIn('virtserialport,chardev=clipboard,name=com.redhat.spice.0', args)
        self.assertIn('virtio-gpu-pci', args)
        self.assertIn('file=' + str(self.disk) + ',if=virtio,format=qcow2', args)
        self.assertIn('user,id=net0,hostfwd=tcp:127.0.0.1:2244-:22', args)
        self.assertEqual(args.count('virtio-serial-pci,id=clipboard-serial'), 1)

    def test_clipboard_can_be_disabled_without_agent_support(self):
        args = self.arguments(VM_CLIPBOARD='0', FAKE_NO_AGENT='1')
        self.assertNotIn('-chardev', args)
        self.assertFalse(any('virtserial' in value for value in args))

    def test_missing_agent_support_fails_before_booting(self):
        result = self.run_launcher(FAKE_NO_AGENT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('lacks qemu-vdagent', result.stderr)
        self.assertFalse(self.log.exists())

    def test_display_override_is_one_argument(self):
        args = self.arguments(QEMU_DISPLAY='cocoa,zoom-to-fit=off')
        self.assertEqual(args[args.index('-display') + 1], 'cocoa,zoom-to-fit=off')

    def test_linux_x86_preserves_default_display(self):
        args = self.arguments(FAKE_SYSTEM='Linux', FAKE_ARCH='x86_64')
        self.assertEqual(args[args.index('-machine') + 1], 'q35')
        self.assertEqual(args[args.index('-display') + 1], 'default')

    def test_invalid_clipboard_setting_is_rejected(self):
        result = self.run_launcher(VM_CLIPBOARD='yes')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('must be 0 or 1', result.stderr)
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
