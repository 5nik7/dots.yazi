#!/usr/bin/env python3
"""Compare the pure Lua resolver to GNU ls using disposable filesystem fixtures."""
import itertools
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import tempfile


def main():
    plugin = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix='dots-ls-colors-') as temporary:
        root = Path(temporary)
        env = os.environ.copy()
        for key in ('HOME', 'XDG_CONFIG_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_RUNTIME_DIR', 'TMPDIR'):
            directory = root / key
            directory.mkdir()
            env[key] = str(directory)
        env.update(TERM='xterm-256color', LC_ALL='C')
        fixtures = root / 'files'
        fixtures.mkdir()
        for name in ('plain', 'a.txt', 'b.tar.gz', 'c.JPG', 'd.JpG', 'e.Jpg', 'with space.txt', '-name.txt', '路径.txt', 'a.a:b', 'a.a=b', 'a.a[1]', 'ex.txt', 'suid.txt', 'sgid.txt', 'hard.txt'):
            (fixtures / name).touch()
        for name, mode in (('ex.txt', 0o755), ('suid.txt', 0o4755), ('sgid.txt', 0o2755)):
            (fixtures / name).chmod(mode)
        hardlink = subprocess.run(['ln', str(fixtures / 'hard.txt'), str(fixtures / 'hard2.txt')], env=env, capture_output=True)
        if hardlink.returncode:
            print('SKIP native hard-link case: filesystem refused creation; covered by Lua fixture')
        for name, mode in (('dir', 0o755), ('sticky', 0o1755), ('writable', 0o777), ('both', 0o1777)):
            (fixtures / name).mkdir()
            (fixtures / name).chmod(mode)
        (fixtures / 'link.txt').symlink_to('a.txt')
        (fixtures / 'dir-link').symlink_to('dir')
        (fixtures / 'broken').symlink_to('absent')
        os.mkfifo(fixtures / 'pipe')
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(str(fixtures / 'socket'))
        try:
            configurations = [
                'fi=0:di=1;34:ln=36:or=1;31:*.txt=4;38;5;123;48;2;1;2;3:*.gz=31:*.tar.gz=32:*.jpg=35',
                'fi=33:ex=0:mh=0:su=0:sg=0:*.txt=31:*.txt=32:*.tar.gz=31:*.gz=32:*.jpg=31:*.JPG=32',
                'fi=0:di=0:ln=target:or=0:ex=0:*.txt=1;31;22;39:*.jpg=31:*.JPG=31',
                r'fi=32:*.a\:b=31:*.a\=b=33:*.a[1]=34:mh=35:tw=36:ow=37:st=90:su=91:sg=92',
                'no=35:fi=:di=:ln=:or=:ex=:mh=:su=:sg=:tw=:ow=:st=:',
                'fi=1;2;3;4;5;6;7;8;9;22;23;24;25;27;28;29;97;100',
            ]
            configurations += [
                f'fi=33:*.jpg={a}:*.JPG={b}:*.Jpg={c}'
                for a, b, c in itertools.product(('31', '32'), repeat=3)
            ]
            cases, expected, labels = [], [], []
            for rules in configurations:
                env['LS_COLORS'] = rules
                for path in sorted(fixtures.iterdir()):
                    metadata = path.stat() if path.exists() else path.lstat()
                    mode = metadata.st_mode
                    cha = dict(
                        is_link=path.is_symlink(), is_orphan=path.is_symlink() and not path.exists(),
                        is_dir=stat.S_ISDIR(mode), is_exec=bool(mode & 0o111), is_sticky=bool(mode & stat.S_ISVTX),
                        is_fifo=stat.S_ISFIFO(mode), is_sock=stat.S_ISSOCK(mode),
                        is_block=stat.S_ISBLK(mode), is_char=stat.S_ISCHR(mode),
                        nlink=metadata.st_nlink, permissions=stat.filemode(mode),
                    )
                    output = subprocess.run(['ls', '--color=always', '-d', '--quoting-style=literal', '--', path.name],
                                            cwd=fixtures, env=env, capture_output=True, check=True).stdout
                    prefix = output.split(os.fsencode(path.name), 1)[0]
                    sequences = re.findall(rb'\x1b\[([0-9;]*)m', prefix)
                    sequence = sequences[-1].decode() if sequences else '0'
                    cases.append(dict(rules=rules, name=path.name, cha=cha))
                    expected.append(dict(rules='fi=' + sequence, name='plain', cha={}))
                    labels.append((rules, path.name, sequence))
            def resolve(items):
                result = subprocess.run(['lua', 'test-ls-colors.lua', '--resolve'], cwd=plugin, env=env,
                                        input=json.dumps(items), text=True, capture_output=True, check=True)
                return json.loads(result.stdout)
            actual, oracle = resolve(cases), resolve(expected)
            for label, a, e in zip(labels, actual, oracle):
                assert a == e, (label, a, e)
            print(f'PASS {len(cases)} GNU ls comparisons (metadata, suffix precedence, colors, resets, escapes)')
        finally:
            sock.close()


if __name__ == '__main__':
    main()
