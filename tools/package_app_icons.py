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
COLORS = dict(blue='#315F95', purple='#7356A6', green='#26745A',
              orange='#A75B29', pink='#AD476B', cyan='#357C85', gray='#675F71')
art = np.array(Image.open(ROOT / 'assets/app-icon-foreground.png').convert('RGBA'))
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


def pale(color, amount):
    rgb = tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))
    return '#' + ''.join(f'{round(v + (255 - v) * amount):02X}' for v in rgb)


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
    for name, color in COLORS.items():
        secondary = '#82A7D5' if name == 'blue' else pale(color, .43)
        background = '#E3EDFC' if name == 'blue' else pale(color, .87)
        (res / f'drawable/launcher_foreground_{name}.xml').write_text(vector(color, secondary))
        # A native layer-list also supports launchers before adaptive icons.
        (res / f'drawable/launcher_{name}.xml').write_text(f'<layer-list xmlns:android="http://schemas.android.com/apk/res/android"><item><shape><solid android:color="{background}"/><corners android:radius="24dp"/><size android:width="108dp" android:height="108dp"/></shape></item><item android:drawable="@drawable/launcher_foreground_{name}"/></layer-list>\n')
        for version in (26, 33):
            folder = res / f'drawable-v{version}'
            folder.mkdir(exist_ok=True)
            mono = '<monochrome android:drawable="@drawable/ic_launcher_monochrome"/>' if version == 33 else ''
            (folder / f'launcher_{name}.xml').write_text(f'<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background><shape><solid android:color="{background}"/></shape></background><foreground android:drawable="@drawable/launcher_foreground_{name}"/>{mono}</adaptive-icon>\n')
    (res / 'values/colors.xml').write_text('<resources>\n    <color name="ic_launcher_background">#E3EDFC</color>\n</resources>\n')
    for version in (26, 33):
        mono = '<monochrome android:drawable="@drawable/ic_launcher_monochrome"/>' if version == 33 else ''
        for suffix in ('', '_round'):
            (res / f'mipmap-anydpi-v{version}/ic_launcher{suffix}.xml').write_text(f'<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/ic_launcher_background"/><foreground android:drawable="@drawable/launcher_foreground_blue"/>{mono}</adaptive-icon>\n')
    cairosvg.svg2png(bytestring=svg(COLORS['blue'], '#82A7D5').encode(), write_to=str(res / 'drawable-nodpi/ic_launcher_brand.png'), output_width=1024, output_height=1024)
    cairosvg.svg2png(bytestring=svg('#000000', '#000000').encode(), write_to=str(res / 'drawable-nodpi/ic_launcher_brand_monochrome.png'), output_width=1024, output_height=1024)
    for density, pixels in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        for suffix in ('', '_round'):
            cairosvg.svg2png(bytestring=svg(COLORS['blue'], '#82A7D5', '#E3EDFC', .9).encode(), write_to=str(res / f'mipmap-{density}/ic_launcher{suffix}.png'), output_width=pixels, output_height=pixels)

# Keep the approved rounded tile for the Windows launcher.
image = Image.open(BytesIO(cairosvg.svg2png(bytestring=svg(COLORS['blue'], '#82A7D5', '#E3EDFC', .9).encode()))).convert('RGBA')
image.save(ROOT / 'windows/mclash/windows/runner/resources/app_icon.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
(ROOT / 'assets/app-icon-foreground.svg').write_text(svg(COLORS['blue'], '#82A7D5'))
print('Packaged Android, Root and Windows app icons.')
