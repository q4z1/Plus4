#!/usr/bin/env python3
"""tracecmp.py a b - two traces of trace.py compared, second by second:
the map, its characters, the screen shown (the pointer's cells as what is
under it), the routes, the trains and the rest of the game's state, each
by its name in the build's labels. The first seconds where something
differs are listed, with what.

tracecmp.py a - what trace a holds at its end (clock, score, trains).
"""
import os
import sys

BASE = 0x0400

# (name, bytes) - found by name in each build; a name one build lacks is
# said once and left out
NAMED = [
    ('_map_w', 1), ('_map_h', 1), ('_code_mask', 256), ('_code_deco', 256),
    ('_code_path', 256), ('_q4', 384), ('_plain', 256), ('_next_code', 1),
    ('_next_q', 1), ('_pool_first', 1), ('_zoom', 1), ('_view_x', 1),
    ('_view_y', 1), ('_view_sx', 1), ('_view_sy', 1), ('_view_cw', 1),
    ('_view_ch', 1), ('_nsig', 1), ('_sig_x', 48), ('_sig_y', 48),
    ('_sig_dir', 48), ('_nportal', 1), ('_portal_x', 12), ('_portal_y', 12),
    ('_nstation', 1), ('_st_name', 192), ('_nplat', 1), ('_pl_station', 32),
    ('_pl_num', 32), ('_pl_x0', 32), ('_pl_y0', 32), ('_pl_x1', 32),
    ('_pl_y1', 32), ('_lv_name', 20), ('_lv_start', 2), ('_lv_perfect', 2),
    ('_lv_ntrains', 1), ('_scr_row', 50),
    ('_st_lx', 12), ('_st_ly', 12),
    ('_ndest', 1), ('_dest_x', 12), ('_dest_y', 12), ('_dest_end', 12),
    ('_dest_len', 12), ('_dest_out', 12), ('_dest_tx', 12), ('_dest_ty', 12),
    ('_dest_dirs', 768), ('_rt_sig', 16), ('_rt_len', 16), ('_rt_out', 16),
    ('_rt_end', 16),
    ('_tt_state', 24), ('_tt_slot', 24), ('_tt_arr', 384), ('_tt_plat', 192),
    ('_tt_pts', 192), ('_train_marked', 1),
    ('_r_state', 8), ('_r_tt', 8), ('_r_visit', 8), ('_r_v', 16),
    ('_r_acc', 16), ('_r_vmax', 16), ('_r_len', 16), ('_r_rem', 16),
    ('_r_sub', 8),
    ('_r_exit', 8), ('_r_halt', 8), ('_r_moved', 8), ('_r_sigstop', 8),
    ('_r_brk', 8), ('_r_platahead', 8), ('_r_until', 16), ('_r_col', 8),
    ('_r_pix', 8), ('_moved', 1), ('_bank', 1), ('_old_from', 1),
    ('_old_to', 1), ('_brake', 192), ('_autopilot_on', 1),
    ('_clock_s', 2), ('_clock_f', 1), ('_speed_i', 1), ('_score', 2),
    ('_perfect', 2), ('_msg_time', 1), ('_ended', 1), ('_panel_t', 1),
    ('_sel_sig', 1), ('_sel_n', 1), ('_sel_x', 12), ('_sel_y', 12),
    ('_sel_alt', 12), ('_cur_x', 1), ('_cur_y', 1),
    ('_clock_txt', 9),
    ('_tc_a', 1), ('_tc_ae', 1), ('_tc_am', 1), ('_tc_b', 1), ('_tc_be', 1),
    ('_tc_bm', 1), ('_tc_o', 2), ('_tc_col', 1), ('_tc_x', 1), ('_tc_y', 1),
    ('_tc_base', 4), ('_tz_q', 1), ('_tz_n1', 1), ('_tz_sh', 1),
    ('_pl_next', 1), ('_pl_end', 1), ('_dl_n', 1), ('_dl_lim', 1),
     ('_ptr_x', 2), ('_ptr_y', 2),
    ('_ptr_w', 2), ('_ptr_h', 2), ('_vorg_x', 2), ('_vorg_y', 2),
    ('_scrn', 2), ('_colr', 2),
]

# fixed places (game.inc, trainschedule.cfg); what is in use of the rest
# (left as it was, it holds what memory held before: it differs from run to
# run) is compared in used()
FIXED = [
    ('font', 0xC000, 0x780), ('cursor chars', 0xC7C0, 0x40),
]


def labels(path):
    lbl = {}
    for line in open(path):
        p = line.split()
        if len(p) == 3 and p[0] == 'al':
            lbl.setdefault(p[2].lstrip('.'), int(p[1], 16))
    return lbl


class Trace:
    def __init__(self, path):
        self.path = path
        self.lbl = labels(os.path.join(path, 'labels'))
        self.n = len([f for f in os.listdir(path) if f.endswith('.bin')])

    def mem(self, i):
        return open(os.path.join(self.path, f'{i:04d}.bin'), 'rb').read()

    def get(self, m, name, size):
        a = self.lbl.get(name, self.lbl.get(name.lstrip('_')))
        if a is None:
            return None
        return m[a - BASE:a - BASE + size]

    def word(self, m, name):
        b = self.get(m, name, 2)
        return b[0] | b[1] << 8

    def screen(self, m):
        """the screen shown, the pointer's cells as what is under them"""
        s = self.word(m, '_scrn')
        c = self.word(m, '_colr')
        chars = bytearray(m[s - BASE:s - BASE + 1000])
        cols = bytearray(m[c - BASE:c - BASE + 1000])
        valid = self.get(m, 'p_valid', 4)
        lo, hi = self.get(m, 'p_olo', 4), self.get(m, 'p_ohi', 4)
        und, ucol = self.get(m, 'p_under', 4), self.get(m, 'p_ucol', 4)
        for k in range(4):
            if valid[k]:
                o = lo[k] | hi[k] << 8
                if o < 1000:
                    chars[o], cols[o] = und[k], ucol[k]
        return bytes(chars), bytes(cols)

    def used(self, m):
        """what is in use of the map, the routes, the rings, the draw
        list: (name, bytes) each"""
        w, h = self.get(m, '_map_w', 1)[0], self.get(m, '_map_h', 1)[0]
        out = [('_row_start', self.get(m, '_row_start', 2 * h))]
        for name, a in (('map code', 0xC800), ('map attr', 0xCE00),
                        ('map occ', 0xD400)):
            out.append((name, m[a - BASE:a - BASE + w * h]))
        sig = self.get(m, '_rt_sig', 16)
        ln = self.get(m, '_rt_len', 16)
        for r in range(16):
            if sig[r] != 255:
                a = 0x0400 + r * 64 - BASE
                out.append((f'rt_dirs[{r}]', m[a:a + ln[r]]))
        st = self.get(m, '_r_state', 8)
        tail, end = self.get(m, '_r_tail', 8), self.get(m, '_r_end', 8)
        for k in range(8):
            if st[k]:
                ring = b''
                i = tail[k]
                while True:
                    for j in range(4):
                        ring += bytes([m[0xE000 + j * 512 + k * 64 + (i & 63) - BASE]])
                    if i == end[k]:
                        break
                    i = (i + 1) & 255
                out.append((f'ring[{k}]', ring))
                # (where in its ring a train is does not matter: how far
                # its head and the end of its authority are from its tail)
                head = self.get(m, '_r_head', 8)[k]
                out.append((f'head/end[{k}]', bytes([(head - tail[k]) & 255,
                                                     (end[k] - tail[k]) & 255])))
        if self.get(m, '_old_from', 1) is None:     # (each train its own
            return out                              # draw list now)
        f, t = self.get(m, '_old_from', 1)[0], self.get(m, '_old_to', 1)[0]
        dl = b''
        i = f
        while i != t:
            for a in (0xEC00, 0xED00, 0xEE00, 0xEF00, 0xF800, 0xF900):
                dl += bytes([m[a + i - BASE]])
            i = (i + 1) & 255
        out.append(('draw list', dl))
        return out


def text(chars):
    rows = []
    for r in range(25):
        s = ''
        for c in chars[r * 40:(r + 1) * 40]:
            c = c & 63 if r >= 19 else c    # the board: extended colour
            s += chr(64 + c) if 1 <= c <= 26 else chr(c) if 32 <= c <= 63 else \
                '#' if 64 <= c < 160 else 'T' if c < 240 else '+'
        rows.append(s)
    return '\n'.join(rows)


def summary(t, i):
    m = t.mem(i)
    print(f'second {i}: clock_s {t.word(m, "_clock_s")}, score '
          f'{int.from_bytes(t.get(m, "_score", 2), "little", signed=True)}, '
          f'ended {t.get(m, "_ended", 1)[0]}')
    print('r_state', list(t.get(m, '_r_state', 8)),
          'tt_state', list(t.get(m, '_tt_state', 24)))
    print(text(t.screen(m)[0]))


def main():
    a = Trace(sys.argv[1])
    if len(sys.argv) < 3:
        summary(a, a.n - 1)
        return
    b = Trace(sys.argv[2])
    names = []
    for name, size in NAMED:
        if a.get(a.mem(0), name, 1) is not None and b.get(b.mem(0), name, 1) is not None:
            names.append((name, size))
        else:
            print(f'not in both: {name}')
    n = min(a.n, b.n)
    if a.n != b.n:
        print(f'lengths differ: {a.n} and {b.n} seconds')
    bad = 0
    for i in range(n):
        ma, mb = a.mem(i), b.mem(i)
        diff = []
        for name, size in names:
            if a.get(ma, name, size) != b.get(mb, name, size):
                diff.append(name)
        for name, addr, size in FIXED:
            x, y = ma[addr - BASE:addr - BASE + size], mb[addr - BASE:addr - BASE + size]
            if x != y:
                k = next(j for j in range(size) if x[j] != y[j])
                diff.append(f'{name} (+${k:03x}: {x[k]:02x} {y[k]:02x})')
        ua, ub = dict(a.used(ma)), dict(b.used(mb))
        for name in sorted(set(ua) | set(ub)):
            if ua.get(name) != ub.get(name):
                diff.append(name)
        sa, sb = a.screen(ma), b.screen(mb)
        if sa[0] != sb[0]:
            k = next(j for j in range(1000) if sa[0][j] != sb[0][j])
            diff.append(f'screen (row {k // 40} col {k % 40})')
        # (the colour of a space shows nowhere)
        k = next((j for j in range(1000) if sa[1][j] != sb[1][j] and
                  (sa[0][j] != 32 or sb[0][j] != 32)), None)
        if k is not None:
            diff.append(f'colours (row {k // 40} col {k % 40})')
        if diff:
            print(f'second {i}: ' + ', '.join(diff))
            bad += 1
            if bad >= 5:
                break
    if not bad:
        print(f'{n} seconds the same')


if __name__ == '__main__':
    main()
