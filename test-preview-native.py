#!/usr/bin/env python3
"""Preview acceptance in private Yazi PTYs; never opens the live DDS/config/cache."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import shlex
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import zlib

ROOT = Path(__file__).resolve().parent
PROBE = r'''--- @sync entry
return { entry = function()
 local result = { same = cx.active.id.value == cx.active.id.value, id = cx.active.id.value,
   skip = cx.active.preview.skip, tabs = #cx.tabs }
 local ok, preview = pcall(require, "dots.preview")
 if ok then
   result.modes = {}
   for _, t in ipairs(preview.tabs or {}) do
     result.modes[#result.modes+1] = {token=t.token, source=t.source, active=t.id==cx.active.id.value}
   end
 end
 local f = assert(io.open(os.getenv("HOME") .. "/probe.json", "w"))
 f:write(ya.json_encode(result));f:close()
end }
'''

class Session:
    def __init__(self, root, config=None, width=80, backend='mdcat', source='bat'):
        self.root, self.output = root, bytearray()
        for name in ('home','config','config-root','cache','state','data','runtime','tmp','work','bin'):
            (root/name).mkdir(parents=True)
        self.cfg = root/'config'
        shutil.copytree(ROOT, self.cfg/'plugins/dots.yazi', ignore=shutil.ignore_patterns('.git','.codex','.agents','__pycache__'))
        if config:
            for name in ('init.lua','yazi.toml','keymap.toml'):
                shutil.copyfile(config/name, self.cfg/name)
        else:
            (self.cfg/'init.lua').write_text('require("dots.preview"):setup({image={renderer="chafa"},markdown={renderer='+json.dumps(backend)+',source='+json.dumps(source)+'}})\n')
            (self.cfg/'yazi.toml').write_text('''[mgr]
ratio=[1,2,5]
[preview]
image_delay=0
[plugin]
prepend_previewers=[
 {url="*.{[mM][dD],[mM][aA][rR][kK][dD][oO][wW][nN],[mM][dD][oO][wW][nN]}",run="dots preview markdown"},
 {mime="text/{markdown,x-markdown}",run="dots preview markdown"},
 {mime="image/{avif,hei?,jxl}",run="dots preview image magick"},
 {mime="image/svg+xml",run="dots preview image svg"},
 {mime="image/*",run="dots preview image image"},
]
''')
            (self.cfg/'keymap.toml').write_text('[[mgr.prepend_keymap]]\non="<A-m>"\nrun="plugin dots -- preview toggle"\n')
        cfg = self.cfg/'yazi.toml'
        text = cfg.read_text()
        if 'cache_dir = ""' in text:
            text = text.replace('cache_dir = ""','cache_dir = '+json.dumps(str(root/'cache')))
        else:
            text = text.replace('[preview]', '[preview]\ncache_dir = '+json.dumps(str(root/'cache')))
        cfg.write_text(text)
        probe = self.cfg/'plugins/probe.yazi';probe.mkdir()
        (probe/'main.lua').write_text(PROBE)
        with (self.cfg/'keymap.toml').open('a') as f:
            f.write('\n[[mgr.prepend_keymap]]\non="~"\nrun="plugin probe"\n')
            f.write('\n[[mgr.prepend_keymap]]\non="!"\nrun="plugin dots -- preview toggle"\n')
        self.log=root/'calls.jsonl'
        for tool in ('mdcat','bat','chafa','glow','rich'):
            real=shutil.which(tool)
            script=root/'bin'/tool
            script.write_text('#!'+sys.executable+'\n'+f'''import json,os,sys,time
from pathlib import Path
with open({str(self.log)!r},'a') as f:f.write(json.dumps([{tool!r},sys.argv[1:],os.getpid()])+"\\n")
mode=Path({str(root/'behavior')!r}).read_text() if Path({str(root/'behavior')!r}).exists() else ''
if {tool!r} in ('mdcat','glow','rich'):
 if mode=='fail':sys.exit(2)
 if mode=='hang':time.sleep(30)
 if mode=='closed':os.close(1);os.close(2);time.sleep(30)
 if mode=='slow':time.sleep(1);print('STALE_RENDER');sys.exit(0)
 if mode=='flood':sys.stdout.write(('x'*1024+'\\n')*9000);sys.exit(0)
if {tool!r} in ('glow','rich'):
 print('\\x1b[31mFIXTURE_RENDER\\x1b[0m');sys.exit(0)
os.execv({real!r},[{tool!r}]+sys.argv[1:])
''')
            script.chmod(0o700)
        self.env={k:v for k,v in os.environ.items() if k in ('PATH','LD_PRELOAD','PREFIX','TERMUX_VERSION')}
        self.env.update(HOME=str(root/'home'),YAZI_CONFIG_HOME=str(self.cfg),XDG_CONFIG_HOME=str(root/'config-root'),
            XDG_CACHE_HOME=str(root/'cache'),XDG_STATE_HOME=str(root/'state'),XDG_DATA_HOME=str(root/'data'),
            XDG_RUNTIME_DIR=str(root/'runtime'),TMPDIR=str(root/'tmp'),TERM='xterm-256color',COLORTERM='truecolor',
            PATH=str(root/'bin')+os.pathsep+self.env['PATH'],YAZI_LOG='debug',GIT_CONFIG_NOSYSTEM='1',GIT_CONFIG_GLOBAL=os.devnull)
        work=root/'work'
        (work/'a - 路径.Md').write_text('# PREVIEW_HEADING\n\n**BOLD_TOKEN** and `CODE_TOKEN`.\n\n'+''.join(f'Paragraph {i:03d} with words to wrap in narrow panes.\n\n' for i in range(100)))
        (work/'b.md').write_text('# SECOND_DOCUMENT\n\nsecond body\n')
        (work/'c.txt').write_text('ordinary text\n')
        (work/'d.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80"><rect width="80" height="80" fill="red"/></svg>')
        def chunk(kind,data):return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data)&0xffffffff)
        (work/'e.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',32,32,8,2,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+bytes([255,0,0])*32)*32))+chunk(b'IEND',b''))
        (work/'f.md').write_bytes(b'x'*(2*1024*1024+1))
        with (self.cfg/'keymap.toml').open('a') as f:
            for key,path in zip('123456',sorted(work.iterdir())):
                f.write('\n[[mgr.prepend_keymap]]\non='+json.dumps(key)+'\nrun='+json.dumps('reveal '+shlex.quote(str(path)))+'\n')
            f.write('\n[[mgr.prepend_keymap]]\non="^"\nrun="tab_swap -1"\n')
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',30,width,0,0))
        def session():os.setsid();fcntl.ioctl(0,termios.TIOCSCTTY,0)
        self.child=subprocess.Popen(['yazi',str(work/'a - 路径.Md')],env=self.env,cwd=work,stdin=slave,stdout=slave,stderr=slave,preexec_fn=session)
        os.close(slave)
        self.pump(1.5)
    def pump(self,seconds=.3):
        end=time.monotonic()+seconds
        while time.monotonic()<end:
            if select.select([self.master],[],[],.03)[0]:
                try:b=os.read(self.master,65536)
                except OSError:break
                self.output.extend(b)
                if b'\x1b[6n' in b:os.write(self.master,b'\x1b[1;1R')
                if b'\x1b[0c' in b or b'\x1b[c' in b:os.write(self.master,b'\x1b[?1;2c')
                if b'\x1b]11;?' in b:os.write(self.master,b'\x1b]11;rgb:0000/0000/0000\x1b\\')
    def key(self,key,delay=.4):os.write(self.master,key);self.pump(delay)
    def calls(self):return [json.loads(x) for x in self.log.read_text().splitlines()] if self.log.exists() else []
    def snapshot(self):
        p=self.root/'home/probe.json';p.unlink(missing_ok=True);self.key(b'~')
        assert p.exists(),self.errors()
        assert p.read_text(),self.errors()
        return json.loads(p.read_text())
    def errors(self):
        p=self.root/'state/yazi/yazi.log'
        return p.read_text()[-4000:] if p.exists() else repr(self.output[-2000:])
    def close(self):
        self.child.kill();self.child.wait(timeout=3)
        # Own the entire private PTY session, including fixture renderer children.
        try:os.killpg(self.child.pid,signal.SIGKILL)
        except ProcessLookupError:pass
        os.close(self.master)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config-dir',type=Path);parser.add_argument('--probe',action='store_true')
    args=parser.parse_args()
    for tool in ('yazi','mdcat','bat','chafa'):
        if not shutil.which(tool):raise SystemExit('Required native tool unavailable: '+tool)
    with tempfile.TemporaryDirectory(prefix='dots-preview-test-') as temp:
        s=Session(Path(temp)/'initial',args.config_dir)
        try:
            if args.probe:
                print(s.snapshot());print(s.errors());return
            assert any(c[0]=='mdcat' for c in s.calls()),s.errors()
            assert b'PREVIEW_HEADING' in s.output,s.errors()
            assert s.snapshot()['same'], 'Yazi numeric tab IDs are unstable'
            s.key(b'\x1bm');assert s.calls()[-1][0]=='bat',s.errors()
            state=s.snapshot();assert any(t['source'] and t['active'] for t in state['modes']),state
            s.key(b'j');assert s.calls()[-1][0]=='bat',s.errors()
            s.key(b'tt');assert s.calls()[-1][0]=='mdcat',s.errors()
            state=s.snapshot();assert state['tabs']==2 and any(not t['source'] and t['active'] for t in state['modes']),state
            s.key(b'^');state=s.snapshot();assert any(not t['source'] and t['active'] for t in state['modes']),state
            s.key(b']');assert s.calls()[-1][0]=='bat',s.errors()
            s.key(b'\x1bm');assert s.calls()[-1][0]=='mdcat',s.errors()
            s.key(b'k');s.key(b'J');assert s.snapshot()['skip']>0,s.errors()
            s.key(b'\x1bm');assert s.snapshot()['skip']==0,s.errors()
            s.key(b'\x03');state=s.snapshot();assert state['tabs']==1 and len(state['modes'])==1,state
            assert not state['modes'][0]['source'],state
            s.key(b'\x1bm')
            print('PASS native mdcat/Bat, Alt+m, tab reordering/closure and scrolling',flush=True)
            s.key(b'3');before=s.snapshot()['modes'];s.key(b'\x1bm');assert s.snapshot()['modes']==before
            for key in (b'4',b'5'):
                s.key(key,.8);assert s.calls()[-1][0]=='chafa',s.errors()
                assert '--symbols' in s.calls()[-1][1] and 'vhalf' in s.calls()[-1][1]
                assert '▄'.encode() in s.output or '▀'.encode() in s.output
            s.key(b'6',.8);before=len(s.calls());s.pump(.5);assert len(s.calls())==before
            s.key(b'1');s.key(b'\x1bm') # back to rendered mode
            for behavior in ('fail','hang','closed','flood'):
                (s.root/'behavior').write_text(behavior)
                s.key(b'2',.2);s.key(b'1',6 if behavior in ('hang','closed') else 1)
                assert s.calls()[-1][0]=='bat',(behavior,s.calls(),s.errors())
            (s.root/'behavior').write_text('slow')
            marker=len(s.output)
            s.key(b'2',.1);s.key(b'\x1bm',1.5)
            s.pump(1.5)
            assert b'STALE_RENDER' not in s.output[marker:],s.errors()
            (s.root/'behavior').unlink()
            s.key(b'\x1bm');s.key(b'1')
            print('PASS non-Markdown guard, SVG/PNG, large files, failures, deadlines, output limit and rapid toggle',flush=True)
            assert 'Error when running previewer'  not in s.errors() and 'runtime error' not in s.errors(),s.errors()
        finally:s.close()
        for width in (40,120):
            s=Session(Path(temp)/('width-'+str(width)),args.config_dir,width=width)
            try:
                assert b'PREVIEW_HEADING' in s.output,s.errors()
                s.key(b'5',.8);assert s.calls()[-1][0]=='chafa',s.errors()
                fcntl.ioctl(s.master,termios.TIOCSWINSZ,struct.pack('HHHH',30,80,0,0));os.kill(s.child.pid,signal.SIGWINCH)
                s.key(b'1',.8);assert s.calls()[-1][0]=='mdcat',s.errors()
                print('PASS native width',width,'and resize',flush=True)
            finally:s.close()
        if not args.config_dir:
            for backend in ('glow','rich','bat','default'):
                s=Session(Path(temp)/backend,backend=backend,source='cat')
                try:
                    if backend in ('glow','rich'):assert b'FIXTURE_RENDER' in s.output,s.errors()
                    elif backend=='bat':assert any(c[0]=='bat' for c in s.calls()),s.errors()
                    else:assert not any(c[0] in ('mdcat','glow','rich','bat') for c in s.calls()),s.errors()
                    before=len(s.calls());s.key(b'\x1bm');assert len(s.calls())==before
                    print('PASS',backend,'adapter and plain source (Glow/Rich use fixtures)',flush=True)
                finally:s.close()

if __name__=='__main__':main()
