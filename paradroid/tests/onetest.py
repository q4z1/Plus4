"""One test at a time: every other test script still running (a run left
in the background, one cut short) is ended before a test starts its
emulator - else the old one goes on driving the emulator or the files
under the new one's feet, and its pictures look like bugs that are not
there. vice.py and yape.py call it before they end the emulators."""
import os
import signal
import time


def _others():
    me = os.getpid()
    mine = set()
    p = me
    while p > 1:                        # this one and what started it
        mine.add(p)
        try:
            p = int(open('/proc/%d/stat' % p).read().rsplit(')', 1)[1].split()[1])
        except OSError:
            break
    out = []
    for d in os.listdir('/proc'):
        if not d.isdigit() or int(d) in mine:
            continue
        try:
            cmd = open('/proc/%s/cmdline' % d, 'rb').read().split(b'\0')
        except OSError:
            continue
        if cmd and os.path.basename(cmd[0]).startswith(b'python') and any(
                b'tests/' in a and a.endswith(b'.py') for a in cmd[1:]):
            out.append(int(d))
    return out


def kill_other_tests():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = _others()
        if not pids:
            return
        for p in pids:
            try:
                os.kill(p, sig)
            except OSError:
                pass
        time.sleep(1)
    if _others():
        raise RuntimeError('other tests still running: %s' % _others())


if __name__ == '__main__':             # build.sh: no build under a test
    import sys
    if _others():
        sys.exit('a test is running (%s): no build under it' %
                 ' '.join(map(str, _others())))
