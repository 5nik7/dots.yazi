#!/usr/bin/env python3
"""Check Githead visibility and query suppression in owned PTYs/tmux sessions."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

PLUGIN = Path(__file__).resolve().parent
PROBE = r'''--- @sync entry
return { entry = function()
 local ok, value = pcall(function()
  local head, git = require('dots.githead'), require('dots.git')
  local dirs = 0
  for _ in pairs(git.dirs) do dirs = dirs + 1 end
  local header = Header:new(ui.Rect { x=0, y=0, w=120, h=1 }, cx.active):redraw()
  local parts = {}
  for _, span in ipairs(Dotline.coloreds.get.githead() or {}) do parts[#parts+1] = span[1] end
  return { hidden=head.hidden, repo=head.name or '', request=head.request or 0,
   text=table.concat(parts), repo_hidden=Dotline.coloreds.get.repo_name() == nil,
   right_width=header[2]:width(), git_dirs=dirs,
   tmux=(os.getenv('TMUX') or '') ~= '', theme=require('dots.theme').snapshot.id }
 end)
 local f=assert(io.open(os.getenv('HOME')..'/probe.jsonl','a'))
 f:write(require('dots.json').encode(ok and value or {failure=tostring(value)}),'\n'); f:close()
end }'''


def run_case(config, in_tmux, enabled):
    with tempfile.TemporaryDirectory(prefix='dots-githead-') as temporary:
        root = Path(temporary)
        for name in ('home', 'config', 'state', 'cache', 'data', 'runtime', 'tmp', 'work', 'bin'):
            (root / name).mkdir()
        cfg = root / 'config'
        shutil.copytree(PLUGIN, cfg / 'plugins/dots.yazi',
                        ignore=shutil.ignore_patterns('.git', '.agents', '.codex', 'tests', '__pycache__'))
        for name in ('init.lua', 'keymap.toml', 'yazi.toml'):
            shutil.copyfile(config / name, cfg / name)
        source = (cfg / 'init.lua').read_text()
        setting = 'hide_in_tmux = ' + str(enabled).lower() + ','
        if re.search(r'\bhide_in_tmux\s*=', source):
            source = re.sub(r'hide_in_tmux\s*=\s*(true|false)\s*,', setting, source)
        else:
            source, count = re.subn(r'(\bgithead\s*=\s*\{)', r'\1\n    ' + setting, source, count=1)
            assert count == 1
        # Exercise the real candidate config; fix only the probe's target layout.
        source += "\nDotline.config.header_line.right = { section_a={}, section_b={{type='coloreds', name='githead'}}, section_c={} }\n"
        (cfg / 'init.lua').write_text(source)
        (cfg / 'plugins/probe.yazi').mkdir()
        (cfg / 'plugins/probe.yazi/main.lua').write_text(PROBE)
        with (cfg / 'keymap.toml').open('a') as file:
            file.write('\n[[mgr.prepend_keymap]]\non="~"\nrun="plugin probe"\n')
            file.write('\n[[mgr.prepend_keymap]]\non="!"\nrun="plugin dots -- githead ' + str(root / 'work') + ' 1"\n')
        env = {k: v for k, v in os.environ.items() if k in ('PATH', 'LD_PRELOAD', 'PREFIX', 'TERMUX_VERSION')}
        env.update(HOME=str(root / 'home'), YAZI_CONFIG_HOME=str(cfg), XDG_CONFIG_HOME=str(cfg),
                   XDG_STATE_HOME=str(root / 'state'), XDG_CACHE_HOME=str(root / 'cache'),
                   XDG_DATA_HOME=str(root / 'data'), XDG_RUNTIME_DIR=str(root / 'runtime'),
                   TMPDIR=str(root / 'tmp'), TERM='xterm-256color', YAZI_LOG='debug',
                   GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
        real_git = shutil.which('git')
        subprocess.run([real_git, 'init', '-b', 'fixture'], cwd=root / 'work', env=env,
                       check=True, capture_output=True, timeout=5)
        (root / 'work/file.txt').write_text('untracked fixture\n')
        commands = root / 'commands.jsonl'
        for program in ('git', 'git-it'):
            target = root / 'bin' / program
            body = ('#!' + sys.executable + '\nimport json, os, sys\n'
                    + 'with open(' + repr(str(commands)) + ', "a") as f: f.write(json.dumps(['
                    + repr(program) + '] + sys.argv[1:]) + "\\n")\n')
            body += ('os.execv(' + repr(real_git) + ', [' + repr(real_git) + '] + sys.argv[1:])\n'
                     if program == 'git' else 'print(\'{"icon":"G","owned":false}\')\n')
            target.write_text(body)
            target.chmod(0o755)
        env['PATH'] = str(root / 'bin') + os.pathsep + env['PATH']
        spec = importlib.util.spec_from_file_location('theme_fixture', PLUGIN / 'test-theme-native.py')
        theme_fixture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(theme_fixture)
        state = root / 'state/dots/themes'
        def publish(name, light=False):
            folder = state / 'generations' / name
            folder.mkdir(parents=True)
            (folder / 'colors.json').write_text(json.dumps(theme_fixture.document(light)))
            (state / 'current').write_text(name + '\n')
        publish('g.dark')
        socket = root / 'tmux.sock'
        tmux = ['tmux', '-S', str(socket), '-f', os.devnull]
        def tmux_run(*args, check=True):
            return subprocess.run([*tmux, *args], env=env, cwd=root, check=check,
                                  capture_output=True, timeout=5)
        master = proc = None
        output = bytearray()
        def pump(seconds=.2):
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                if master is None:
                    time.sleep(.04)
                elif select.select([master], [], [], .04)[0]:
                    try: data = os.read(master, 65536)
                    except OSError: break
                    output.extend(data)
                    if b'\x1b[6n' in data: os.write(master, b'\x1b[1;1R')
                    if b'\x1b[c' in data or b'\x1b[0c' in data: os.write(master, b'\x1b[?1;2c')
                    if b'\x1b]11;?' in data: os.write(master, b'\x1b]11;rgb:0000/0000/0000\x1b\\')
        def key(value):
            if in_tmux: tmux_run('send-keys', '-t', 'fixture:0.0', '-l', value)
            else: os.write(master, value.encode())
            pump()
        def snapshot():
            path = root / 'home/probe.jsonl'
            before = len(path.read_text().splitlines()) if path.exists() else 0
            key('~')
            for _ in range(25):
                rows = path.read_text().splitlines() if path.exists() else []
                if len(rows) > before:
                    result = json.loads(rows[-1])
                    assert 'failure' not in result, result
                    return result
                pump()
            raise AssertionError('No Yazi probe response: ' + repr(output[-1200:]))
        hidden = in_tmux and enabled
        def check():
            value = snapshot()
            assert value['tmux'] == in_tmux and value['hidden'] == hidden, value
            assert value['git_dirs'] > 0, value
            if hidden:
                assert value['text'] == '' and value['repo_hidden'] and value['repo'] == '', value
                assert value['right_width'] == 0 and value['request'] == 0, value
            else:
                assert 'work' in value['text'] and 'fixture' in value['text'], value
                assert value['right_width'] > 0 and not value['repo_hidden'], value
            return value
        try:
            if in_tmux:
                tmux_run('new-session', '-d', '-s', 'fixture', '-x', '120', '-y', '30',
                         shlex.join(['yazi', str(root / 'work')]))
            else:
                master, slave = pty.openpty()
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 120, 0, 0))
                def session():
                    os.setsid()
                    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
                proc = subprocess.Popen(['yazi', str(root / 'work')], stdin=slave, stdout=slave,
                                        stderr=slave, env=env, cwd=root, preexec_fn=session)
                os.close(slave)
            pump(2)
            check()
            # A direct queued job must also obey the UI-owned hidden state.
            if hidden: key('!')
            publish('g.light', True)
            subprocess.run(['ya', 'pub-to', '0', 'dots-theme-changed', '--str', str(state.parent)],
                           env=env, check=True, capture_output=True, timeout=5)
            pump(.5)
            assert check()['theme'] == 'test-light'
            for width in (40, 80, 120):
                if in_tmux: tmux_run('resize-window', '-t', 'fixture:0', '-x', str(width), '-y', '30')
                else: fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 30, width, 0, 0))
                pump()
                check()
            logged = [json.loads(row) for row in commands.read_text().splitlines()]
            assert any('--porcelain' in call for call in logged), logged
            header_calls = [call for call in logged if call[0] == 'git-it' or '--ignore-submodules=dirty' in call
                            or '--show-toplevel' in call or 'log' in call or '@{upstream}' in call]
            assert bool(header_calls) != hidden, header_calls
            print(f'PASS native tmux={in_tmux}, hide_in_tmux={enabled}: header layout, query suppression, '
                  'file Git fetching, live theme refresh and 40/80/120 columns', flush=True)
            key('q')
            if proc is not None: assert proc.wait(timeout=3) == 0
        finally:
            if in_tmux: tmux_run('kill-server', check=False)
            if proc is not None:
                if proc.poll() is None: proc.kill()
                proc.wait(timeout=3)
            if master is not None: os.close(master)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config-dir', type=Path, default=PLUGIN / 'tests/fixtures/config')
    config = parser.parse_args().config_dir.resolve()
    for in_tmux, enabled in ((False, True), (True, True), (True, False)):
        run_case(config, in_tmux, enabled)
