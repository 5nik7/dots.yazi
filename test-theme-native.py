#!/usr/bin/env python3
"""Native Yazi dark/light and last-good refresh in private homes and DDS sockets."""
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import struct
import subprocess
import tempfile
import termios
import time

PLUGIN = Path(__file__).resolve().parent
PROBE = '''--- @sync entry
return { entry = function()
 local ok, value = pcall(function()
  local theme = require('dots.theme')
  local colors = require('dots'):colors()
  local file = cx.active.current.hovered
  return { id=theme.snapshot and theme.snapshot.id or '', error=theme.last_error,
   blue=colors and colors.blue or '', dir=colors and colors.type.dir or '',
   callable=require('dots').colors().background, reversed=Dotline.config.style_a.reversed,
   fg=Dotline.config.style_a.fg, normal=Dotline.config.style_a.bg_mode.normal,
   unset=Dotline.config.style_a.bg_mode.un_set,
   mode=cx.active.mode.is_select and 'V' or cx.active.mode.is_unset and 'U' or 'N',
   name=file and file.name, mime=file and file:mime(),
   file=file and require('dots.ls-colors'):style(file):raw() or {} }
 end)
 local f=assert(io.open(os.getenv('HOME')..'/probe.jsonl','a'))
 f:write(require('dots.json').encode(ok and value or {failure=tostring(value)}),'\\n'); f:close()
end }'''


def document(light=False):
    colors = dict(background='#eeeeee' if light else '#111111', foreground='#111111' if light else '#eeeeee',
                  blue='#123456' if light else '#89b4fa', red='#bb1111' if light else '#ff6666',
                  magenta='#663399' if light else '#cba6f7')
    types = {k: {'fg': colors[c]} for k,c in [('file','foreground'),('dir','blue'),('executable','red')]}
    groups = dict(type=types, mime={'text/*':{'fg':colors['red']}}, extension={})
    colors.update({g:{k:v['fg'] for k,v in styles.items()} for g,styles in groups.items()})
    def sgr(value): return '0;38;2;'+';'.join(str(int(value[i:i+2],16)) for i in (1,3,5))
    return dict(schema=1,id='test-light' if light else 'test-dark',mode='light' if light else 'dark',colors=colors,styles=groups,
                ls_colors='di='+sgr(colors['blue'])+':fi='+sgr(colors['foreground'])+':ex='+sgr(colors['red']),
                provenance={g:{k:{'fg':'/fixture/user/file-colors.toml'} for k in values} for g,values in groups.items()})


def main():
    with tempfile.TemporaryDirectory(prefix='dots-yazi-theme-') as temporary:
        root=Path(temporary)
        for name in ('home','config','state','cache','data','runtime','tmp','work'): (root/name).mkdir()
        cfg=root/'config'; target=cfg/'plugins/dots.yazi'
        shutil.copytree(PLUGIN,target,ignore=shutil.ignore_patterns('.git','.agents','.codex','tests'))
        (cfg/'plugins/probe.yazi').mkdir();(cfg/'plugins/probe.yazi/main.lua').write_text(PROBE)
        (cfg/'init.lua').write_text("""local dots=require('dots')
dots:setup({theme={source='dots'},dotline={style_a={fg=dots.colors.background,reversed=false,
 bg_mode={normal=dots.colors.blue,select=dots.colors.magenta,un_set=dots.colors.red}}},
 githead={repo_color=dots.colors.git.repo,repo_owned_color=dots.colors.git.repo_owned}})""")
        (cfg/'keymap.toml').write_text('[[mgr.prepend_keymap]]\non="~"\nrun="plugin probe"\n')
        (root/'work/directory').mkdir(); (root/'work/file.txt').write_text('fixture')
        state=root/'state/dots';(state/'themes/generations').mkdir(parents=True)
        def publish(name,doc):
            folder=state/'themes/generations'/name;folder.mkdir()
            (folder/'colors.json').write_text(json.dumps(doc))
            (state/'themes/new').write_text(name+'\n');(state/'themes/new').replace(state/'themes/current')
        publish('g.dark',document())
        env={k:v for k,v in os.environ.items() if k in ('PATH','LD_PRELOAD','PREFIX','TERMUX_VERSION')}
        env.update(HOME=str(root/'home'),YAZI_CONFIG_HOME=str(cfg),XDG_CONFIG_HOME=str(cfg),
                   XDG_STATE_HOME=str(root/'state'),XDG_CACHE_HOME=str(root/'cache'),XDG_DATA_HOME=str(root/'data'),
                   XDG_RUNTIME_DIR=str(root/'runtime'),TMPDIR=str(root/'tmp'),TERM='xterm-256color',
                   GIT_CONFIG_NOSYSTEM='1',GIT_CONFIG_GLOBAL=os.devnull)
        master,slave=pty.openpty();fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',30,80,0,0))
        def session(): os.setsid();fcntl.ioctl(0,termios.TIOCSCTTY,0)
        proc=subprocess.Popen(['yazi',str(root/'work')],stdin=slave,stdout=slave,stderr=slave,env=env,cwd=root,preexec_fn=session)
        os.close(slave);output=bytearray()
        def pump(seconds=.2):
            deadline=time.monotonic()+seconds
            while time.monotonic()<deadline:
                if select.select([master],[],[],.04)[0]:
                    try: data=os.read(master,65536)
                    except OSError: break
                    output.extend(data)
                    if b'\x1b[6n' in data: os.write(master,b'\x1b[1;1R')
                    if b'\x1b[c' in data or b'\x1b[0c' in data: os.write(master,b'\x1b[?1;2c')
                    if b'\x1b]11;?' in data: os.write(master,b'\x1b]11;rgb:0000/0000/0000\x1b\\')
        def snapshot():
            path=root/'home/probe.jsonl';before=len(path.read_text().splitlines()) if path.exists() else 0
            os.write(master,b'~')
            for _ in range(25):
                pump()
                rows=path.read_text().splitlines() if path.exists() else []
                if len(rows)>before:
                    value=json.loads(rows[-1]);assert 'failure' not in value,value;return value
            raise AssertionError('Yazi did not answer: '+repr(output[-1200:]))
        def notify():
            subprocess.run(['ya','pub-to','0','dots-theme-changed','--str',str(state)],env=env,check=True,capture_output=True,timeout=3)
            pump(.4)
        try:
            pump(1)
            initial=snapshot();assert initial['id']=='test-dark',initial
            assert initial['callable']=='#111111' and initial['reversed'] is False,initial
            assert initial['normal']=='#89b4fa' and initial['file']['fg']=='#89B4FA',initial
            os.write(master,b'j');pump(1)
            textfile=snapshot();assert textfile['name']=='file.txt' and textfile['mime']=='text/plain',textfile
            assert textfile['file']['fg']=='#FF6666',textfile
            suffix=document();suffix['styles']['extension']['.txt']={'fg':'#cba6f7'}
            suffix['colors']['extension']['.txt']='#cba6f7'
            suffix['provenance']['extension']['.txt']={'fg':'/fixture/user/rules.toml'}
            suffix['ls_colors']+=':*.txt=0;38;2;203;166;247'
            publish('g.suffix',suffix);notify()
            assert snapshot()['file']['fg']=='#CBA6F7'
            os.write(master,b'k');pump()
            publish('g.light',document(True));notify()
            light=snapshot();assert light['id']=='test-light' and light['normal']=='#123456' and light['fg']=='#eeeeee',light
            assert light['file']['fg']=='#123456',light
            for key,mode in ((b'v','V'),(b'\x1b','N'),(b'V','U'),(b'\x1b','N')):
                os.write(master,key);pump();assert snapshot()['mode']==mode
            for columns in (40,80,120):
                fcntl.ioctl(master,termios.TIOCSWINSZ,struct.pack('HHHH',30,columns,0,0));pump();assert snapshot()['id']=='test-light'
            bad=document();bad['colors']['blue']='invalid'
            publish('g.invalid',bad);notify()
            last=snapshot();assert last['id']=='test-light' and last['error'],last
            notify();assert snapshot()['normal']=='#123456'
            invalid=document();invalid['provenance']['mime']['text/*']['fg']=42
            publish('g.invalidsource',invalid);notify();assert snapshot()['id']=='test-light'
            gitdoc=document();gitdoc['styles']['git']={'repo':{'fg':'#223344','bold':False,'bg':'reset'}}
            gitdoc['colors']['git']={'repo':'#223344'};gitdoc['provenance']['git']={'repo':{'fg':'fixture'}}
            publish('g.git',gitdoc);notify();assert snapshot()['id']=='test-dark'
            gitdoc['styles']['git']['repo']['bold']='invalid'
            publish('g.badgit',gitdoc);notify();assert snapshot()['error']
            publish('g.recovered',document());notify();assert snapshot()['id']=='test-dark'
            assert b'Failed to' not in output,repr(output[-1000:])
            print('PASS native dark/light publication, MIME/suffix styles, N/V/U redraws, 40/80/120 columns, last-good retention and recovery')
        finally:
            if proc.poll() is None: proc.kill()
            proc.wait(timeout=3);os.close(master)

if __name__=='__main__': main()
