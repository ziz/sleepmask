# Sleepmask - a wrapper for RemGlk

## RemGlk?

The CheapGlk [Glk][glk] library allows playing interactive fiction
through a dumb terminal interface, such as IRC or a chat server,
without the need for cursor positioning and similar;
unfortunately, it has the significant lack that it cannot handle
anything but a single buffer output window; no status bars,
multiple windows, or any of the other fancy things that the Glk
standard is capable of handling.

[RemGlk][remglk] is a Glk library that, rather than displaying to
a screen or console, handles input and output via JSON-serialized
events.

## So how does that help with CheapGlk?

Sleepmask seeks to bridge the gap between dumb terminals and
full-featured IF by wrapping up RemGlk in a human-friendly dumb
terminal interface. It maintains the state of grid buffers and
prints them out in their entirety when they are updated; it
outputs all line buffers as they are updated; it provides both
line-based and character-based input (through the `/key <x>`
metacommand).

## Sounds great!  How do I use it?

Install the required gems - yajl-ruby and the development version of
eventmachine.

Download and compile RemGlk - at the time of writing, you'll also
need the [save file name hack][savefile] to enable saving and
loading.

Download and compile your favorite Glk-enabled IF interpreter
(for instance, [Glulxe][glulxe], the Glulx reference interpreter)
against RemGlk.

Edit sleepmachine.rb to point it at the location of your
interpreter(s).

(Get an appropriate story file - for instance, the venerable
[Adventure][adventure] has `advent.ulx` available.)

Run it:

~~~~
ruby sleepmachine.rb --interpreter glulxe ../advent.ulx
~~~~

Type commands normally. 

If you use the commands `SAVE` or `RESTORE`, sleepmask will
automatically prompt you for a filename; if your game does not use
those commands for saving and restoring, you will need to type
`/savename <filename>` before you attempt to save or restore to
tell sleepmask what filename to use.

If you need to press a key (rather than enter a line of input),
use the `/key <key>` metacommand - any (non-whitespace) (latin-1) single
character, or one of the special character names:

space, left, right, up, down, return, delete, escape, tab, pageup,
pagedown, home, end, func1, func2, func3, func4, func5, func6,
func7, func8, func9, func10, func11, func12

`/quit` will quit the interpreter.

## Known limitations

* No differentiation between different line buffer windows.
* No support for hyperlink input.
* No way to query and interrogate the current state of grid
  buffers that are not being updated.
* Bad interpreter configuration support (currently hardcoded)

## License

Copyright (c) 2012 Justin de Vesine

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use, copy,
modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

[remglk]: https://github.com/erkyrath/remglk
[glk]: http://eblong.com/zarf/glk/index.html
[savefile]: https://github.com/erkyrath/remglk/issues/1
[glulxe]: https://github.com/erkyrath/glulxe
[adventure]: http://ifdb.tads.org/viewgame?id=fft6pu91j85y4acv
