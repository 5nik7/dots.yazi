#!/usr/bin/env python3
"""Exercise native ya package materialization using an offline, test-owned Git repo."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parent
SKILLS = ('dots-yazi-ui', 'dots-yazi-validation')


def main():
    for tool in ('git', 'ya'):
        if not shutil.which(tool):
            raise SystemExit(f'Required native tool unavailable: {tool}')
    with tempfile.TemporaryDirectory(prefix='dots-yazi-package-') as temporary:
        root = Path(temporary)
        for name in ('home', 'config', 'cache', 'state', 'data', 'runtime', 'tmp'):
            (root / name).mkdir(mode=0o700)
        source = root / 'source'
        shutil.copytree(ROOT, source, symlinks=True,
                        ignore=shutil.ignore_patterns('.git', '__pycache__', '*.pyc'))
        env = {k: v for k, v in os.environ.items() if k in ('PATH', 'LD_PRELOAD', 'PREFIX', 'TERMUX_VERSION')}
        env.update(HOME=str(root / 'home'), XDG_CONFIG_HOME=str(root / 'config'),
                   YAZI_CONFIG_HOME=str(root / 'config/yazi'), XDG_CACHE_HOME=str(root / 'cache'),
                   XDG_STATE_HOME=str(root / 'state'), XDG_DATA_HOME=str(root / 'data'),
                   XDG_RUNTIME_DIR=str(root / 'runtime'), TMPDIR=str(root / 'tmp'),
                   GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=str(root / 'gitconfig'),
                   GIT_TERMINAL_PROMPT='0', GIT_ALLOW_PROTOCOL='file', TERM='dumb')
        (root / 'config/yazi').mkdir()
        (root / 'gitconfig').write_text(
            '[user]\n name = Fixture\n email = fixture@example.invalid\n'
            '[commit]\n gpgSign = false\n'
            f'[url "{source.as_uri()}"]\n'
            ' insteadOf = https://github.com/5nik7/dots.yazi.git\n'
            ' insteadOf = https://github.com/5nik7/dots.yazi\n')

        def run(*args, expected=0):
            result = subprocess.run(args, cwd=source, env=env, text=True,
                                    capture_output=True, timeout=30)
            if expected is not None:
                assert result.returncode == expected, result.stdout + result.stderr
            return result

        run('git', 'init', '-b', 'main')
        # Reproduce the released directory-link failure entirely in the fixture.
        for name in SKILLS:
            path = source / '.agents/skills' / name
            assert path.is_dir() and not path.is_symlink(), path
            shutil.rmtree(path)
            path.symlink_to('../../.codex/skills/' + name, target_is_directory=True)
        run('git', 'add', '.')
        run('git', 'commit', '-m', 'Fixture with unsupported directory links')
        failed = run('ya', 'pkg', 'add', '5nik7/dots', expected=None)
        assert failed.returncode != 0 and 'neither a regular file' in failed.stdout + failed.stderr, failed
        print('PASS native reproduction of directory-symlink packaging failure', flush=True)

        for name in SKILLS:
            path = source / '.agents/skills' / name
            path.unlink()
            shutil.copytree(ROOT / '.agents/skills' / name, path, symlinks=True)
        run('git', 'add', '.')
        run('git', 'commit', '-m', 'Fixture with package-compatible skill links')
        run('ya', 'pkg', 'add', '5nik7/dots')
        installed = root / 'config/yazi/plugins/dots.yazi'
        assert (installed / 'main.lua').read_bytes() == (ROOT / 'main.lua').read_bytes()
        for module in ROOT.glob('*.lua'):
            if module.name.startswith('test'):
                continue
            assert (installed / module.name).read_bytes() == module.read_bytes(), module.name
        # Skills belong to the source checkout; ya only installs plugin runtime files.
        cached = next((root / 'cache/yazi/packages').iterdir())
        for name in SKILLS:
            directory = cached / '.agents/skills' / name
            assert directory.is_dir() and not directory.is_symlink(), directory
            for file in ('SKILL.md', 'agents/openai.yaml'):
                assert (directory / file).read_bytes() == (ROOT / '.codex/skills' / name / file).read_bytes()
        manifest = tomllib.loads((root / 'config/yazi/package.toml').read_text())
        assert manifest['plugin']['deps'][0]['use'] == '5nik7/dots'
        run('ya', 'pkg', 'install')
        print('PASS native add recovery, complete runtime materialization, valid skill links and repeated install', flush=True)


if __name__ == '__main__':
    main()
