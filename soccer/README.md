# Soccer for the Commodore Plus/4

A soccer game after **Sensible Soccer** (Sensible Software, 1992-1994,
Amiga), drawn the way **Arlasoft Soccer** draws it on the C64: a ground
larger than the screen that scrolls in eight directions, small players
with their shadows, the stands and the boards around the pitch.

**Work in progress.** What is there: the whole ground, both teams lined up
for the kick-off, the ball, and the player of yours nearest to it, who
dribbles it and passes it; the view follows the ball. Still to come: the
shot, the other players running, the keepers, the rules, the match.

![The kick-off](screenshots/kickoff.png)

## Controls

| Joystick (either port) | Keyboard | |
| --- | --- | --- |
| directions | cursor keys | run, and dribble the ball at your feet |
| fire | space | pass, to the team-mate the way you face |

## Building and running

```sh
soccer/build.sh          # -> soccer/build/soccer.prg
soccer/run-yape.sh       # in Yape, with the gamepad set up as for Paradroid
soccer/run.sh            # in VICE
```

In VS Code, F5 with any file of the folder open builds and starts it.
`tools/mkdata.py` makes the data the game is built with from the text
files in `data/`.

## How it plays

The match runs on Sensible Soccer's pitch and in its units, 50 times a
second, as Sensible Soccer moves things: a player or the ball always
heads for a point at a speed, the ball rolls and flies with its friction,
gravity and bounce, a dribbled ball is kicked on just ahead of the player
whenever it is at his feet, and a pass goes to the nearest team-mate
within an eighth of a turn of the way you face, harder the further he
is. The ground the C64 draws is shorter than Sensible Soccer's pitch, so
the game's lengths are squeezed onto it: across one to one, along by
about nine sixteenths.

## How it is drawn

The Plus/4 has no sprites, so a player is drawn into the characters under
him. There are three pictures, each with a colour matrix, a code matrix
and a character set of its own: one is shown, a finished one may be
waiting, and the third is being drawn. The interrupt puts the waiting one
on screen in the vertical blank, with the fine scroll it was drawn for,
never sooner than two frames after the last - an even 25 pictures a
second. A picture that costs more than two frames to draw (the view has
just moved by a whole cell) borrows the time from the cheaper one before
it.

When the view has moved by a cell or two since a picture was last drawn,
its codes are not looked up afresh but moved over in memory, and only the
rows and columns coming in are looked up.

The ground is 79 x 67 cells of 221 different characters - too many to sit
in a character set next to the players'. But a screen never shows more
than 76 of them, so each picture's set holds only those it shows, given
codes as they are first met while the picture is built; the codes from
136 on are the players'. A cell a player covers gets one of those: the
ground's character is copied into it and the player goes in through a
mask. Each picture keeps a list of the cells its players took and puts
them back before it is drawn again.

The C64 has two colours for a sprite besides its own; a multicolour
character on the TED shares three with the whole screen and has one of
its own. The grass, black and the players' skin are the shared ones, and
a cell's own colour is the shirt of the player in it - or white, for the
lines. Where a player stands on a line, that bit of line takes his
colour.

![Running, the view following](screenshots/running.png)

It is a fan-made proof of concept, not affiliated with or endorsed by
Sensible Software or Arlasoft.
