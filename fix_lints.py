import os
import re

def fix_file(filepath, fixes):
    with open(filepath, 'r') as f:
        content = f.read()
    
    for old, new in fixes:
        content = content.replace(old, new)
        
    with open(filepath, 'w') as f:
        f.write(content)

# Fix Share.share
fix_file('lib/features/tracking/live_tracking_screen.dart', [
    ('Share.share', 'Share.share') # actually the hint says "Use SharePlus instead" but SharePlus is in share_plus package? Wait, share is deprecated, use Share.share from share_plus?
])
