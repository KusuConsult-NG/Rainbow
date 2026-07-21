from PIL import Image
import glob
import os

files = glob.glob('/Users/mac/RainBow/ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png')
for file in files:
    try:
        img = Image.open(file)
        if img.mode in ('RGBA', 'LA') or (img.mode == 'P' and 'transparency' in img.info):
            background = Image.new('RGB', img.size, (255, 255, 255))
            if img.mode == 'RGBA':
                background.paste(img, mask=img.split()[3])
            else:
                background.paste(img)
            background.save(file, "PNG")
            print(f"Removed alpha channel for: {os.path.basename(file)}")
    except Exception as e:
        print(f"Failed to process {file}: {e}")
