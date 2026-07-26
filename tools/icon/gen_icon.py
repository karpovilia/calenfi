#!/usr/bin/env python3
# Генератор иконки Calenfi — вариант «Григорианский Витрувий» (A):
# буква С (плоские торцы, не полумесяц) как фигура в центре круга; круг и квадрат
# смещены и перекрываются (общая нижняя касательная) — витрувианская конструкция;
# радиальные спицы из центра-«пупка» + мелкая сетка; палитра cyanotype (синий/белый).
#
# Пишет три SVG в tools/icon/:
#   calenfi_icon.svg  — полный тайл (macOS/Windows/Linux/legacy Android)
#   bg.svg            — фон adaptive-иконки (синий + сетка, full-bleed)
#   calenfi_fg.svg    — передний план adaptive-иконки (фигура в safe-zone)
import math, os

OUT = os.path.dirname(os.path.abspath(__file__))

BG   = "#1E4E8C"   # синий фон
INK  = "#F5FBFF"   # белая буква
LINE = "#CFE6FF"   # конструкционные линии
GRID = "#BFE0FF"   # сетка

SX0, SY0, S = 212, 240, 600
BASE = SY0 + S           # 840 — общая нижняя касательная круга и квадрата
R = 330
CXc = 512.0
CYc = BASE - R           # 510 — центр круга («пупок»)

def c_path(cx, cy, Ro=240.0, Ri=144.0, h=90.0):
    xoT = cx + math.sqrt(Ro*Ro - h*h); xiT = cx + math.sqrt(Ri*Ri - h*h)
    yT = cy - h; yB = cy + h
    return (f"M {xoT:.2f} {yT:.2f} A {Ro} {Ro} 0 1 0 {xoT:.2f} {yB:.2f} "
            f"L {xiT:.2f} {yB:.2f} A {Ri} {Ri} 0 1 1 {xiT:.2f} {yT:.2f} Z")

def c_layer():
    return (f'<path d="{c_path(CXc, CYc)}" fill="{INK}" '
            f'stroke="#12467F" stroke-width="2" filter="url(#sh)"/>')

def circle():
    return f'<circle cx="{CXc}" cy="{CYc}" r="{R}" fill="none" stroke="{LINE}" stroke-width="5" opacity="0.92"/>'

def square():
    return (f'<rect x="{SX0}" y="{SY0}" width="{S}" height="{S}" rx="4" '
            f'fill="none" stroke="{LINE}" stroke-width="5" opacity="0.92"/>')

def radial(n=24, w=1.6, op=0.5, r1=R):
    out = []
    for i in range(n):
        a = math.radians(i * 360.0 / n)
        x = CXc + r1 * math.cos(a); y = CYc + r1 * math.sin(a)
        out.append(f'<line x1="{CXc}" y1="{CYc}" x2="{x:.1f}" y2="{y:.1f}"/>')
    return f'<g stroke="{LINE}" stroke-width="{w}" opacity="{op}" stroke-linecap="round">{"".join(out)}</g>'

def grid(step=48, w=1, op=0.12):
    ln = []
    for i in range(step, 1024, step):
        ln.append(f'<line x1="{i}" y1="0" x2="{i}" y2="1024"/>')
        ln.append(f'<line x1="0" y1="{i}" x2="1024" y2="{i}"/>')
    return f'<g stroke="{GRID}" stroke-width="{w}" opacity="{op}">{"".join(ln)}</g>'

# фигура без сетки (для safe-zone переднего плана)
def figure():
    return radial(24) + square() + circle() + c_layer()

HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
DEFS = ('<defs><filter id="sh" x="-25%" y="-25%" width="150%" height="150%">'
        '<feDropShadow dx="0" dy="8" stdDeviation="14" flood-color="#0A2A50" flood-opacity="0.35"/>'
        '</filter><clipPath id="tile"><rect width="1024" height="1024" rx="224"/></clipPath></defs>')

def master():
    return (f'{HEAD}\n{DEFS}\n<rect width="1024" height="1024" rx="224" fill="{BG}"/>\n'
            f'<g clip-path="url(#tile)">\n{grid(48)}\n{figure()}\n</g>\n</svg>')

def background():
    # full-bleed, без скругления — лаунчер сам маскирует
    return (f'{HEAD}\n<rect width="1024" height="1024" fill="{BG}"/>\n{grid(48)}\n</svg>')

def foreground():
    # фигура в safe-zone adaptive-иконки (~0.64 от 108dp)
    return (f'{HEAD}\n{DEFS}\n'
            f'<g transform="translate(512,512) scale(0.64) translate(-512,-510)">\n{figure()}\n</g>\n</svg>')

open(os.path.join(OUT, "calenfi_icon.svg"), "w").write(master())
open(os.path.join(OUT, "bg.svg"), "w").write(background())
open(os.path.join(OUT, "calenfi_fg.svg"), "w").write(foreground())
print("wrote calenfi_icon.svg, bg.svg, calenfi_fg.svg")
