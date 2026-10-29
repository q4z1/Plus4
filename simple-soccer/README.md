# Simple Soccer for the Commodore Plus/4

A soccer game after **Sensible Soccer** (Sensible Software, 1992-1994,
Amiga), drawn the way **Arlasoft Soccer** draws it on the C64: a ground
larger than the screen that scrolls in eight directions, small players
with their shadows, the stands and the boards around the pitch.

**Work in progress.** What is there: the whole ground, both teams in
their formation, the player of yours nearest the ball, who dribbles it,
passes it and shoots, with aftertouch, the other team going for the
ball, the keepers, sliding tackles, headers, and the rules - throw-ins,
goal kicks, corners, fouls with free kicks and penalties, goals and
kick-offs, the score and the time; the view
follows the ball. One player against the computer, or two against each
other, with 35 national teams from all over the world to choose from -
a match, or training: a keeper and two a side, to try the moves out.

![The title](screenshots/title.png) ![The kick-off](screenshots/kickoff.png)

## Controls

| Joystick (either port) | Keyboard | |
| --- | --- | --- |
| directions | cursor keys | run, and dribble the ball at your feet |
| none | | stand - meet a pass, stop a ball that comes to you |
| fire, tapped | space | pass, to the team-mate the way you face; takes a throw-in, corner, goal kick or kick-off |
| fire, the other team on the ball | space | sliding tackle, the way you face |
| fire, held | space | shot - then the stick bends it across, or lifts it pulled back |
| fire, the ball at head height | space | header, the way the stick points (fire may be held as the ball comes) |
| fire, the ball in the air before you | space | diving header |

With one player the joystick in either port (or the keyboard) runs the
home team. With two, the first joystick (and the keyboard) runs the home
team and the second the away team, each the same way. (The code and the
rest of this text call them the cyan and the yellow team, the colours
they had before there was a choice.)

## Building and running

```sh
simple-soccer/build.sh       # -> simple-soccer/build/simple-soccer.d64 (and .prg, the game alone)
simple-soccer/run-yape.sh    # in Yape, with the gamepad set up as for Paradroid
simple-soccer/run.sh         # in VICE
```

In VS Code, F5 with any file of the folder open builds and starts it.
`tools/mkdata.py` makes the data the game is built with from the text
files in `data/`.

## The disk

The game comes on a disk, `simple-soccer.d64`: `LOAD"*",8,1` and `RUN`
(or `LOAD"SIMPLE SOCCER",8`). The first program, the boot (`boot.s`),
puts up its loading screen at once - the name, a football turning, and
"LOADING" with its dots running - and keeps it going while it loads the
flags and the game, and while the game unpacks itself (it is packed by
exomizer: 21 KB on the disk, 49 KB in memory). On a 1541 (any of them),
1570 or 1571 it loads with the fast loader taken over from trainschedule
(`drive.s`, `fastload.s`); on any other drive - a 1551, an SD2IEC - the
KERNAL's way, slower, the screen the same. The border turns red while a
file will not load (no disk, a bad one); it tries again by itself.

The ball is worked out by `tools/mkspinner.py`: a sphere with the twelve
black pentagons of a football round the corners of an icosahedron,
turning about one of them, eight pictures of 24 x 24 pixels; a fifth of
a turn brings a football back to how it was, so they go round without a
jump.

The title shows the two teams' flags side by side, framed, "VS" between
them and each team's name below its own (`data/flags.txt`, drawn by
`tools/mkflags.py`). A flag is 6 x 4 multicolour cells, 48 x 32 pixels,
3 to 2: a third of its width is two cells, so stripes down in thirds lie
on the cells' edges. A cell has four colours - the title's background, a
navy blue that is the flags' navy (the frame keeps it from the
background), white and red, which all cells share, and one of its own -
so most flags come out to the pixel: the stripes, the Union Jack and the
stars of Australia and New Zealand, the USA's canton, Korea's circle,
Canada's leaf (the small emblems drawn pixel for pixel). Where a cell
would need two colours of its own - Brazil's green and yellow - the cells
its yellow lozenge runs through are yellow, their green the navy of its
globe: the lozenge keeps its straight edges. No colour shows that is not
in the flag.

The patterns of all the flags' cells are on the disk once each (184 of
them); the title copies those of the two flags shown into the character
codes its own font leaves free. Each side has two sets of codes: a flag
chosen is made ready in the set not on the screen, and only its 24
cells change over, below the picture's last line - a flag is never seen
half drawn, and the screen is multicolour throughout (the name's
colours too are ones a multicolour screen leaves to text). A team cannot
play itself: choosing passes the other side's team by.

## How it plays

The match runs on Sensible Soccer's pitch and in its units, 50 times a
second, as Sensible Soccer moves things: a player or the ball always
heads for a point at a speed, the ball rolls and flies with its friction,
gravity and bounce, a dribbled ball is kicked on just ahead of the player
whenever it is at his feet (going up, beside his right foot, where he
does not hide it - so a turn up and to the right keeps it, other turns
lose it more often than not, as in Sensible Soccer: the ball does not
stick to his feet), and a pass goes to a team-mate, harder the
further he is: the nearest within 22.5 degrees of the way you face -
unless one up to 67.5 degrees off it is under seven tenths as far; only
with no one in either does it run on by itself. Fire let go before the ball has
come to you passes it as it comes, first time. Fire held for nine frames shoots instead, rising; for the next ten
frames the stick bends the ball to one side if it is pushed across the
shot, and on the fifth it lifts it - high when pulled back, less when let
go or across. The C64 runs its match on the same pitch, in the same
pixels, and so does this game: a pixel of the pitch is a pixel on the
screen, up and down as across - the ground is shown as the C64 shows it,
its plain rows of grass between the boxes and the centre circle, and
beside the goals, repeated (`data/rows.txt`).

For a kick-off the teams line up as on the C64 - the team kicking off
with a forward at the ball, another beside him and its wingers up on the
halfway line, the other team out of the centre circle - and stand till
the ball is played.

Everyone else keeps to his place in the team's formation (`data/tactics.txt`,
eight of them, 4-4-2 for now): each player has an area, and where the ball
is on the pitch decides where in it he stands - he runs there. The yellow
team sends its player nearest the ball after it. A cyan player with the
ball he stays on, a little faster than him, and it is his once it is
right at his feet, nearer him than the cyan player. With it he takes it
towards the cyan goal and shoots from close in - or, a cyan player at
him or after a moment on the ball, passes it on to the team-mate furthest
on, who goes to meet it.
Its next nearest goes along: between the ball and his goal while the
cyan team has it, ahead of it, there to be passed to, while his own does.

As in Sensible Soccer and on the C64, the cyan player nearest a ball his
team has not got - not yours, not the keeper - runs to it on his own, as
a pass's receiver does to meet it. The joystick stays with the player
who has the ball at his feet, goes to whoever of your team gets to it,
and else to the player nearest it - not the one on his way to it, not
the one who has just passed or shot. Your player's shirt flickers white,
so you see whom you run. As in Sensible Soccer, the
players make up their minds every second frame; everyone moves every
frame. A new place in the formation does not send a player sprinting: he goes
as fast as gets him there by about when the next one comes, his feet as
fast as he goes, gliding along with the play instead of hopping.

Over a touch line the ball goes to the other team for a throw-in; over a
goal line, between the posts and under the bar, it is a goal and the
other team kicks off; else a goal kick or a corner, by who touched it
last. The ball is dead for a moment first - it rolls on, the net holds it
after a goal - then it is put down with the taker behind it. When it is
the cyan team's, the stick turns him and fire takes it (a pass, or held,
a shot); the yellow team passes to the nearest team-mate. He turns only
the ways Sensible Soccer lets him: into the pitch and towards the other
goal - up to 90 degrees off for a kick-off, a throw-in, a goal kick and
the keeper's kick, 45 for a corner and a penalty - and any way for a free
kick. The penalty areas and spots are as its rules have them, the spots
107 and 631, 58 pixels out from the goal lines.

A throw-in is thrown: the taker stands behind the touch line facing the
pitch, the ball held up behind his head, and throws it with his arms
going forward - the ball leaving his hands from up there and dropping
in a short curve. Its two pictures, each way, are drawn for this game,
not the C64's.

The player a pass goes to runs to meet it, and the joystick is his once
he has it. Each ball that comes to your player from someone else - a
pass, a loose ball - he takes with a first touch as it reaches him:
stopped at his feet, or, now and then, too heavy a touch that leaves it
running on at half its speed.

## The players' skills

Every player has five skills, 0 to 7, which decide what Sensible
Soccer's players decide by theirs: his pace (how fast he runs, with the
ball and after it), his control (how surely his first touch takes the
ball, how close he keeps it dribbling, how rarely a touch runs away from
him), his tackling (how often he wins the ball off a player who has it),
his heading (how far off a ball he still reaches with his head) and his
shooting (how hard he shoots). Each comes from his place in the team -
the backs tackle and head, the midfielders keep the ball, the wingers
are fast, the forwards shoot - from how good his team is (0 to 4, in
`title.s`'s list of teams) and from a step up or down of his own, the
same for a team in every match. The title works them out once both
teams are chosen.

Where the skills meet, the game rolls for it: a take by the yellow
chaser comes off with 6 + his tackling - the dribbler's control chances
in 16 (and once missed, not again for half a second), a sliding tackle
that reaches the ball with 10 + tackling - control; a first touch to a
pass with 10 + control in 16 (a slower ball with 4 more); a dribbler's
touch runs away from him with 7 - control in 128.

A sliding tackle from behind - the tackler facing within 45 degrees of
the way the player on the ball faces - that gets to him before it gets
to the ball is a foul: the whistle, the player fouled down, and a free
kick for his team where he lies; in the penalty area his team attacks,
a penalty. For a free kick the other team's players within 40 pixels of
the ball stand off between it and their goal, a wall; for a penalty the
ball is on the spot, the keeper on his line, and everyone else but the
taker out of the area. The taker faces the goal; yours turns with the
stick and kicks with fire as for any set piece - held, it is a shot -
and the yellow team shoots its penalties at one corner or the other.
Its players do not slide in, so the fouls are yours.

The referee counts each player's fouls: his second brings a yellow card,
his fourth a second yellow and so a red one. The card is shown by him
while the ball is dead; with a red he is off when play goes on - not
drawn, never in reach of the ball, no one's to pass to, the joystick
gone to a team-mate - and his team plays on with ten.

A ball in the air goes over the players' heads unless one of them goes
for it: with fire down as it comes to his head - 11 to 22 high, within
10 pixels - your player jumps and heads it on, the way the stick points
or he faces, as fast as a pass and a little rising; with fire pressed as
it comes at him lower and further off - 4 to 16 high, 10 to 30 pixels
before him - he dives for it, as a sliding tackle in the air, and heads
it on as hard as a shot if he gets to it. The yellow chaser heads a ball
that comes to his head on towards the cyan goal. There are no crosses
as such, as in Sensible Soccer: a shot lifted with the aftertouch is
one.

A ball is a team's while its player who touched it last has it by him,
or for a few frames after a kick: the other team cannot just run it
off him. You win it with a sliding tackle - fire - which knocks it on
the way you slide, if your tackling beats his control; the yellow
chaser wins it by getting to it first or by a take, right at the
dribbler's feet - the same roll (see the skills).

The TED's two voices give the match its sounds, played by the interrupt
50 times a second: a thump for every pass and shot, a softer one for
the keeper's catch, the referee's whistle - a trill - at a kick-off,
three blasts at half and full time, and the crowd roaring at a goal.

A title comes first: the name, a gold cup between its words, the length of the match (3, 5 or 7
minutes), one player or two, a match or training, and the home and the away team to choose -
the stick up and down to a line, left and right on it - fire to kick
off. Each of the 35 teams has its shirt and a second one: the TED gives a
multicolour cell's own colour only the hues 0-7 (black, white, red, cyan,
purple, green, blue, yellow) in eight shades, so the Netherlands play in
a light red and the green teams in a dark green the grass sets off. The
away team wears its second shirt when its first is the home team's
colour. A team's name on the title shows the shirt it will play in. On
a light shirt the joystick's player flickers black instead of white. It is loaded where the
pictures go once the match is on, and runs before them.

With two players the yellow team is run just as the cyan one: what a
player's control of his team is - his joystick, the player it runs, fire
held, the pass on its way, the aftertouch, the dribble, the team - is
one block of variables, and the routines that use it (`control`, the
joystick passed on, the team-mate running to a free ball, the
aftertouch) run once for each team, the yellow team's block swapped in
for its turn. The yellow team's own mind - its chaser, the one in
support, its passes and set pieces - rests meanwhile; its keeper keeps
his goal on his own, as the cyan one does.

## Training

MODE: TRAINING on the title makes the match a training game: each team
plays with its keeper, its central midfielder on the right (8) and its
centre forward (10) - the others are off the pitch from the start, as if
sent off - and there is no clock: no half time, no end, the minute
stays at 0. Everything else is as in a match - the kick-off, the rules,
the set pieces, the cards - and one player or two, so every move can be
tried out on an open pitch.

`tests/moves.py` makes a video of the moves in training, from the disk
in Yape: `build/simple-soccer-moves.mp4`, a scene each - dribbling, a
pass and its first touch, a one-two, shots, the aftertouch's bend and
lob, a header and a diving header, a sliding tackle, a foul and its
card, a free kick, a penalty, a corner, a throw-in - with a caption that
says what the joystick does. Each scene is set up in the running match:
the game is held at the start of a frame (in a loop of its own, as Yape's
monitor stops the CPU in the middle of an instruction), the players and
the ball are put in place, and the stick's moves go in as a plan by the
match's frames. The players showing a move have the skills that make it
come off - a first touch, a tackle and a dribble are rolled for.

## The title's music

The title plays **Kernkraft 400** (Zombie Nation, 1999), the stadium
anthem, and through it David Whittaker's **Star Dust**, tune 21 of
*Lazy Jones* (C64, 1984), which Kernkraft 400 is made of: the riff and
the octave bass as Lazy Jones plays them (read from its SID tune), the
kick on every beat and the hi-hat between them as Kernkraft 400 adds
them - a lead-in as Kernkraft 400 builds up, two bars of the beat
alone and five with the bass, then the riff four times, the third over
the hi-hats alone, and round again from the lead-in
(`data/title-music.txt`).

**The player that sounds it is taken over from International Karate on
the Plus/4** - System 3's game of 1986, whose title plays Rob Hubbard's
music, as brought over from the C64 by ATI (code), CSABO (audio), SIZ
(the loader) and TLC (the digis), so its disk's directory names them:
its mixer, "Wave Convert V2.0" by TLC of CNS (1992), as it is. It gets three voices with waves of their own out of a machine
that has two squares: the TED's sound in its "digital" mode makes the
volume register a 4-bit DAC, and a timer interrupts 5542 times a second
to add up the three voices. That interrupt is some sixty bytes in the
zero page that rewrite themselves - each voice's phase is the low byte
of the address it reads its wave from, its step and its wave page are
operands, and the sample it adds up waits as the operand the next
interrupt writes out first, so every sample comes at the same moment.
A wave page holds a wave (two pulses, a saw, noise) at a level 0-3; the
three voices' pages add up to the volume.

What drives it is the game's own (`music.s`): once a frame it goes on
with each voice's notes, walks its instrument's levels frame by frame -
the TED has no envelopes, and neither has the mixer - lets the kick's
pitch fall and gives the noise a random step, and puts it all into the
interrupt's operands. International Karate drives the mixer with a SID
emulation under Hubbard's own player; a tune written for it needs none.
The wave pages are made at the start, where the match's pictures go
later, and the interrupt ends with the title - the match has the TED's
two voices to itself again.

`tools/mkmusic.py` makes the notes into bytes for the player, and with
`--wav file.wav` plays them as the player does, to listen to without a
Plus/4; `tests/title_music.py` records the title in VICE (`--yape`: in
Yape, as a video with its sound).

A match is 90 minutes in three real ones (or five, or seven). At 45 the referee blows for
half time, the teams change ends and the yellow team kicks off; at 90 the result stays
till fire starts a new match. While the ball is dead for a kick-off -
after a goal, at half time, at the start - the score and the minute
show at the top left of the view.

A keeper stands between his posts a little out from his line, further
out the further the ball, and goes a quarter of the ball's way across.
The rest he does as Sensible Soccer's keeper does - read from its code
(c12fce, c109ce) and measured in it, shot for shot, against this game:
a shot at his goal - crossing his line between 263 and 344 - he lets
come till it is in the box, then edges across to where it will cross,
slowly (192: its teams' 176 - 208); he dives at the last moment, once
it is 16 pixels from him and crosses as far from him as his dive gets
in the frames it still takes, or further - his dive's pace guessed anew
each time, as its keeper guesses it (3 to 6.5 pixels a frame, mostly
5.5). He dives at 2048, slowing after two frames, some 60 pixels in
all, and is down 40 frames. A ball that comes right at him (3 pixels)
he catches; one he gets to diving (6 pixels across) bounces off him,
out to the side and away from his goal, at three quarters of its speed.
A slow ball low and near him (some 70 pixels) he goes for (896) and
picks up. So shots at him are held, ones by the posts and across him
mostly parried, a hard one into a corner from close in now and then
goes in - as in Sensible Soccer, where the same shots end the same way
but for chance. One higher than he gets - a lob - goes over him. His
dive is drawn level in the air, his arms on ahead
- pictures drawn for this game (the C64's lean over at 45 degrees and,
without their shadows, look like a player falling over); a diving
header has them too.

At a penalty he does as Sensible Soccer's keeper does (its c109ce): he
waits on his line till the ball is 12 pixels from it - one time in four
20 - and dives then, whatever: to the side it crosses on (straight at
him, to his right), one time in four the wrong way and slower. A
penalty bent into a corner with the aftertouch mostly goes in; one
straight at him he still gets to, his dive too late to take him away
from it.

## How it is drawn

The Plus/4 has no sprites, so a player is drawn into the characters under
him. There are three pictures, each with a colour matrix, a code matrix
and a character set of its own: one is shown, a finished one may be
waiting, and the third is being drawn. The interrupt puts the waiting one
on screen in the vertical blank, with the fine scroll it was drawn for,
never sooner than three frames after the last - an even 16.7 pictures a
second (`PACE=2 simple-soccer/build.sh` for 25, which a full screen of players
cannot keep up). A picture that costs more than three frames to draw
borrows the time from the cheaper one before it. The match itself runs
50 times a second whatever the pictures do.

When the view has moved by a cell or two since a picture was last drawn,
its codes are not looked up afresh but moved over in memory, and only the
rows and columns coming in are looked up.

The ground is 79 x 103 cells (67 different rows) of 221 different characters - too many to sit
in a character set next to the players'. But a screen never shows more
than 76 of them, so each picture's set holds only those it shows, given
codes as they are first met while the picture is built; the codes from
112 on are the players'. A column of a player gets as many of those as it
covers cells, one after the other, so that their pixels lie one after
the other in the character set: the column goes into that strip in one
run. Over grass its pixels go straight in; where a line or another
player is under it, that is copied into the strip first and the player
goes in through a mask. Each picture keeps a list of the cells its
players took, with what they showed before, and puts them back before
it is drawn again. A cache that fills up gives back the codes its
picture does not show - found in one pass over its codes - before it
runs full, and never for two pictures running.

The C64 has two colours for a sprite besides its own; a multicolour
character on the TED shares three with the whole screen and has one of
its own. The shared ones are the grass, black, and one light colour -
the lightest red, near white - that is the lines, the nets, the ball
and the players' skin at once. A cell's own colour is a player's shirt
where he has a bit of shirt in it; with nothing on the pitch in that
colour, a player can take any cell and nothing under him changes. (Two
players of different teams in one cell: the one behind loses his shirt
there.) The socks are black, and neither the players nor the goals cast
a shadow.

Where the TED does more than the C64, the game uses it: a cell's own
colour can be any of eight hues in eight shades, so every spectator in
the stands wears a shirt of his own instead of the C64's white, and the
boards along the pitch show the name in letters two cells wide - the
C64's one-cell letters cannot make an M - each in a colour of a sweep
from yellow to red or cyan to blue, on black. Those cells get their
colours from a map of the rows that have them, put in again only when
the view has moved. Now and then a wave runs through the stands: the
spectators of one kind after another raised a pixel - they sit side by
side in that order, so the raise runs along the rows (the characters
in each picture's cache rewritten, whatever codes they have there).

![The stands and the boards](screenshots/stands.png)

![Running, the view following](screenshots/running.png)

It is a fan-made proof of concept, not affiliated with or endorsed by
Sensible Software or Arlasoft.
