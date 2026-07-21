import glob
import os
from PIL import Image

# 13-inch iPad Pro (M4) Portrait Resolution
target_size = (2064, 2752)

source_dir = '/Users/mac/RainBow/screenshots/'
out_dir = os.path.join(source_dir, '13_inch_ipad')

os.makedirs(out_dir, exist_ok=True)

# Also create 12.9 inch just in case (2048 x 2732)
out_dir_12_9 = os.path.join(source_dir, '12_9_inch_ipad')
os.makedirs(out_dir_12_9, exist_ok=True)
target_size_12_9 = (2048, 2732)

files = glob.glob(os.path.join(source_dir, '*.jpeg'))

for idx, file in enumerate(files):
    try:
        img = Image.open(file)
        
        # We will create a blurred background from the original image to avoid squishing
        # 1. Resize original to cover the target size (with crop) for the background
        # 2. Blur it
        # 3. Paste the original image (scaled to fit height or width) on top
        
        # 13 inch
        background_13 = img.resize(target_size, Image.Resampling.LANCZOS)
        from PIL import ImageFilter
        background_13 = background_13.filter(ImageFilter.GaussianBlur(50))
        
        # Calculate size to fit
        img_ratio = img.width / img.height
        target_ratio = target_size[0] / target_size[1]
        
        if img_ratio < target_ratio:
            # Image is narrower, fit to height
            new_h = target_size[1]
            new_w = int(new_h * img_ratio)
        else:
            # Image is wider, fit to width
            new_w = target_size[0]
            new_h = int(new_w / img_ratio)
            
        fg_13 = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
        
        # Paste
        offset_13 = ((target_size[0] - new_w) // 2, (target_size[1] - new_h) // 2)
        background_13.paste(fg_13, offset_13)
        
        out_name_13 = os.path.join(out_dir, f'ipad_13_{idx+1}.png')
        background_13.save(out_name_13, 'PNG')
        
        # 12.9 inch
        background_12 = img.resize(target_size_12_9, Image.Resampling.LANCZOS)
        background_12 = background_12.filter(ImageFilter.GaussianBlur(50))
        
        target_ratio_12 = target_size_12_9[0] / target_size_12_9[1]
        if img_ratio < target_ratio_12:
            new_h_12 = target_size_12_9[1]
            new_w_12 = int(new_h_12 * img_ratio)
        else:
            new_w_12 = target_size_12_9[0]
            new_h_12 = int(new_w_12 / img_ratio)
            
        fg_12 = img.resize((new_w_12, new_h_12), Image.Resampling.LANCZOS)
        offset_12 = ((target_size_12_9[0] - new_w_12) // 2, (target_size_12_9[1] - new_h_12) // 2)
        background_12.paste(fg_12, offset_12)
        
        out_name_12 = os.path.join(out_dir_12_9, f'ipad_12_9_{idx+1}.png')
        background_12.save(out_name_12, 'PNG')
        
        print(f"Processed {os.path.basename(file)} -> 13 inch & 12.9 inch iPad")
        
    except Exception as e:
        print(f"Failed to process {file}: {e}")

print("Done! Check 13_inch_ipad and 12_9_inch_ipad folders.")
