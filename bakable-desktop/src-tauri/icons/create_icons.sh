#!/bin/bash
# Create placeholder icons using sips (macOS built-in)

# Create a simple 1024x1024 PNG with text using ImageMagick or just copy a placeholder
# For now, create minimal valid PNGs

# Minimal valid 32x32 PNG (dark gray square)
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00 \x00\x00\x00 \x08\x02\x00\x00\x00\xfc\x18\xed\xa3\x00\x00\x00\x1eIDATx\x9cc\xfc\x0f\x00\x00\x01\x01\x00\x05\x18\xd8H\x00\x00\x00\x00IEND\xaeB`\x82' > 32x32.png

# Copy for other sizes
cp 32x32.png 128x128.png
cp 32x32.png 128x128@2x.png  
cp 32x32.png icon.png

echo "Placeholder icons created"
