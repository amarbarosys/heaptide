# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 AMARBARO · amarbaro.org labs
# heaptide_gui FILE: a report's text in an imkit window (heaptide report DIR --gui). The wheel scrolls; closing the window exits.
from std.os import getenv
from std.sys import argv, exit, stderr
from max.gpu.host import DeviceContext
from imkit.draw import UW, UH
from imkit.font import Font
from imkit.layer import Layer
from imkit.theme import amarbaro
from imkit.ui import Ui
from imkit.window import Window

comptime FW = Float32(UW)
comptime FH = Float32(UH)
comptime LINE = Float32(16)  # one report line, px
comptime TOP = Float32(44)  # the first line, below the panel title


def main() raises:
    var args = argv()
    if len(args) != 2:
        print("usage: heaptide_gui FILE", file=stderr)
        exit(2)
    var path = String(args[1])
    var lines = List[String]()
    for line in open(path, "r").read().split("\n"):
        lines.append(String(line))
    var heads = List[Bool]()  # an unindented line names a section
    for line in lines:
        heads.append(line.byte_length() > 0 and not line.startswith(" "))
    var u = Ui(Font(getenv("IMKIT_FONT", "/usr/share/fonts/TTF/Roboto-Medium.ttf"), [13, 16, 22]))
    u.set_theme(amarbaro())
    var ctx = DeviceContext()
    var layer = Layer(ctx, u)
    var win = Window("heaptide " + path, UW, UH, UW, UH, app_id="heaptide")
    var bg = List[UInt32](length=UW * UH, fill=u.theme.panel)
    var title = String("heaptide report")
    var shown = Int((FH - TOP - 16.0) / LINE)  # lines that fit the panel
    var off = 0
    while True:
        var inp = win.poll()
        if inp.quit:
            break
        off = max(0, min(off - Int(inp.wheel * 3.0), max(0, len(lines) - shown)))
        u.begin(inp)
        u.panel(16, 16, FW - 16, FH - 16, title)
        u.clip(16, 16, FW - 16, FH - 16)
        for i in range(min(shown, len(lines) - off)):
            var k = off + i
            _ = u.text(32, TOP + LINE * Float32(i), lines[k], 0, u.theme.accent if heads[k] else u.theme.text)
        u.unclip()
        u.finish()
        layer.render(u)
        win.present(Int(bg.unsafe_ptr()), Int(layer.pixels.unsafe_ptr()))
