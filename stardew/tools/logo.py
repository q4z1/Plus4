#!/usr/bin/env python3
"""logo.py - how the title's letters in data/hud.txt were made.

The letters of STARDEW POND from a 5 x 7 font, each font pixel one
multicolour pixel wide and two lines high, outlined in black, the lowest
line of every stroke in light brown: a letter is 2 x 2 characters, an
icon of the toolbar's character set. The top half in light yellow, the
bottom half a shade darker (the cells' colours).

    tools/logo.py      the icons, to paste at the end of hud.txt
"""
FONT = {
    'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
    'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
    'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
    'D': ['###..', '#..#.', '#...#', '#...#', '#...#', '#..#.', '###..'],
    'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
    'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
    'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
    'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    'N': ['#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#', '#...#'],
}


def letter(rows):
    fill = [[False] * 8 for _ in range(16)]
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c == '#':
                fill[1 + 2 * y][1 + x] = fill[2 + 2 * y][1 + x] = True
    out = []
    for y in range(16):
        line = ''
        for x in range(8):
            if fill[y][x]:
                below = y < 15 and fill[y + 1][x]
                line += '#' if below else 'o'
            elif any(fill[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                     if 0 <= y + dy < 16 and 0 <= x + dx < 8):
                line += 'x'
            else:
                line += '.'
        out.append(line)
    return out


if __name__ == '__main__':
    for ch in 'STARDEWPON':
        print(f'icon LOGO_{ch} col=yellow7,yellow7,yellow5,yellow5')
        print('\n'.join(letter(FONT[ch])))
        print()
