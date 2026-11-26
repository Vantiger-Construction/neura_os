"""Pack locally rendered PNGs. Requires Pillow only at artwork build time."""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('frames', type=Path)
    parser.add_argument('--output', type=Path, default=Path('assets/images'))
    parser.add_argument('--preview', type=Path)
    args = parser.parse_args()
    manifest = json.loads((args.frames / 'render-manifest.json').read_text())
    count, columns, width, height = 32, 8, 160, 240
    if (manifest['frame_count'], manifest['frame_width'], manifest['frame_height']) != (count, width, height):
        raise ValueError('Expected 32 frames at 160 x 240')
    atlas = Image.new('RGBA', (columns * width, (count // columns) * height))
    bounds = []
    for index in range(count):
        frame = Image.open(args.frames / f'frame_{index:02}.png').convert('RGBA')
        if frame.size != (width, height):
            raise ValueError(f'Wrong frame size: {index}')
        bound = frame.getchannel('A').getbbox()
        if bound is None or not (0 < bound[0] < bound[2] < width and 0 < bound[1] < bound[3] < height):
            raise ValueError(f'Empty or clipped frame: {index}')
        bounds.append(bound)
        atlas.paste(frame, ((index % columns) * width, (index // columns) * height))
    args.output.mkdir(parents=True, exist_ok=True)
    atlas_path = args.output / 'neura_startup_turntable.png'
    front_path = args.output / 'neura_startup_front.png'
    atlas.save(atlas_path, optimize=True)
    atlas.crop((0, 0, width, height)).save(front_path, optimize=True)
    manifest.update({
        'columns': columns,
        'rows': count // columns,
        'atlas_width': atlas.width,
        'atlas_height': atlas.height,
        'atlas_decoded_rgba_bytes': atlas.width * atlas.height * 4,
        'frame_alpha_bounds': bounds,
        'atlas_sha256': hashlib.sha256(atlas_path.read_bytes()).hexdigest(),
        'front_sha256': hashlib.sha256(front_path.read_bytes()).hexdigest(),
    })
    (args.output / 'neura_startup_turntable.json').write_text(json.dumps(manifest, indent=2) + '\n')
    if args.preview:
        # Match Flutter's Cubic(0.42, 0, 0.58, 1), including its x inversion.
        def eased(progress):
            low, high = 0.0, 1.0
            for _ in range(30):
                t = (low + high) / 2
                x = 3 * (1-t)**2 * t * 0.42 + 3 * (1-t) * t*t * 0.58 + t**3
                if x < progress:
                    low = t
                else:
                    high = t
            return 3 * (1-t) * t*t + t**3

        preview = []
        for step in range(46):
            index = int(eased(step / 45) * count + 0.5) % count
            left, top = (index % columns) * width, (index // columns) * height
            frame = atlas.crop((left, top, left + width, top + height))
            card = Image.new('RGBA', (320, 320), '#0d0d1a')
            card.alpha_composite(frame, ((card.width - width) // 2, 36))
            draw = ImageDraw.Draw(card)
            draw.text((12, 10), 'Neura startup turn - 900 ms', fill='#e9dcff')
            draw.text((12, 286), 'Rendered artwork preview', fill='#c3b5d9')
            draw.text((12, 302), 'Windows appearance still needs testing', fill='#9d95b0')
            preview.append(card.convert('RGB'))
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        preview[0].save(args.preview, save_all=True, append_images=preview[1:],
                        duration=[20] * 45 + [700], loop=0, optimize=True)
    print(json.dumps({
        'atlas_bytes': atlas_path.stat().st_size,
        'decoded_bytes': manifest['atlas_decoded_rgba_bytes'],
        'manifest': str(args.output / 'neura_startup_turntable.json'),
    }))


if __name__ == '__main__':
    main()
