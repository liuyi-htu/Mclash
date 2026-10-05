"""Package the approved artwork as Android vectors, density icons and Windows ICO.

Run with Pillow, NumPy, OpenCV and CairoSVG installed. Generated resources are
checked in; normal client builds do not run this script.
"""
from pathlib import Path
from io import BytesIO
import cv2
import numpy as np
from PIL import Image
import cairosvg

ROOT = Path(__file__).resolve().parents[1]
PRIMARY = '#315F95'
SECONDARY = '#82A7D5'
BACKGROUND = '#E3EDFC'
art = np.array(Image.open(ROOT / 'assets/app-icon.png').convert('RGBA'))
size = art.shape[0]


def paths(mask):
    contours, _ = cv2.findContours(mask.astype(np.uint8) * 255,
                                  cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    output = []
    for contour in contours:
        if abs(cv2.contourArea(contour)) < size * size * .0003:
            continue
        points = cv2.approxPolyDP(contour, size * .0007, True).reshape(-1, 2)
        output.append('M' + ' L'.join(f'{x},{y}' for x, y in points) + ' Z')
    return ' '.join(output)


alpha = art[:, :, 3] > 128
outline = paths(alpha)
light = paths(alpha & (art[:, :, 0] > 75) & (art[:, :, 1] > 125))


def svg(color, secondary, background=None, factor=.8):
    inset = size * (1 - factor) / 2
    tile = '' if background is None else f'<rect width="{size}" height="{size}" rx="{size * .24}" fill="{background}"/>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">{tile}<g transform="translate({inset} {inset}) scale({factor})"><path fill="{color}" fill-rule="evenodd" d="{outline}"/><path fill="{secondary}" fill-rule="evenodd" d="{light}"/></g></svg>'


def vector(color, secondary, monochrome=False):
    inset = size * .1
    accents = '' if monochrome else f'<path android:fillColor="{secondary}" android:fillType="evenOdd" android:pathData="{light}"/>'
    return f'<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="{size}" android:viewportHeight="{size}"><group android:scaleX="0.8" android:scaleY="0.8" android:translateX="{inset}" android:translateY="{inset}"><path android:fillColor="{color}" android:fillType="evenOdd" android:pathData="{outline}"/>{accents}</group></vector>\n'


for client in ('android', 'root'):
    res = ROOT / client / 'android/app/src/main/res'
    (res / 'drawable/ic_launcher_monochrome.xml').write_text(vector('#000000', '#000000', True))
    (res / 'drawable/ic_launcher_foreground.xml').write_text(vector(PRIMARY, SECONDARY))
    (res / 'values/colors.xml').write_text('<resources>\n    <color name="ic_launcher_background">#E3EDFC</color>\n</resources>\n')
    for version in (26, 33):
        mono = '<monochrome android:drawable="@drawable/ic_launcher_monochrome"/>' if version == 33 else ''
        for suffix in ('', '_round'):
            (res / f'mipmap-anydpi-v{version}/ic_launcher{suffix}.xml').write_text(f'<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/ic_launcher_background"/><foreground android:drawable="@drawable/ic_launcher_foreground"/>{mono}</adaptive-icon>\n')
    cairosvg.svg2png(bytestring=svg(PRIMARY, SECONDARY).encode(), write_to=str(res / 'drawable-nodpi/ic_launcher_brand.png'), output_width=1024, output_height=1024)
    cairosvg.svg2png(bytestring=svg('#000000', '#000000').encode(), write_to=str(res / 'drawable-nodpi/ic_launcher_brand_monochrome.png'), output_width=1024, output_height=1024)
    for density, pixels in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        for suffix in ('', '_round'):
            cairosvg.svg2png(bytestring=svg(PRIMARY, SECONDARY, BACKGROUND, .9).encode(), write_to=str(res / f'mipmap-{density}/ic_launcher{suffix}.png'), output_width=pixels, output_height=pixels)

# Render the same fixed tile for the Windows launcher.
image = Image.open(BytesIO(cairosvg.svg2png(bytestring=svg(PRIMARY, SECONDARY, BACKGROUND, .9).encode()))).convert('RGBA')
image.save(ROOT / 'windows/mclash/windows/runner/resources/app_icon.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
(ROOT / 'assets/app-icon.svg').write_text(svg(PRIMARY, SECONDARY))
print('Packaged Android, Root and Windows app icons.')
