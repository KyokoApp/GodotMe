from PIL import Image
import os

src = "assets/icon/ic_launcher.png"
base = "android/app/src/main/res"

launcher_sizes = {
    "mipmap-mdpi":    48,
    "mipmap-hdpi":    72,
    "mipmap-xhdpi":   96,
    "mipmap-xxhdpi":  144,
    "mipmap-xxxhdpi": 192,
}

# 2.25x dari launcher_sizes — untuk adaptive icon Android 8+
foreground_sizes = {
    "mipmap-mdpi":    108,
    "mipmap-hdpi":    162,
    "mipmap-xhdpi":   216,
    "mipmap-xxhdpi":  324,
    "mipmap-xxxhdpi": 432,
}

img = Image.open(src).convert("RGBA")

for folder, size in launcher_sizes.items():
    d = os.path.join(base, folder)
    os.makedirs(d, exist_ok=True)
    resized = img.resize((size, size), Image.LANCZOS)
    resized.save(os.path.join(d, "ic_launcher.png"))
    resized.save(os.path.join(d, "ic_launcher_round.png"))
    print(f"✅ {folder}: ic_launcher {size}x{size}")

for folder, size in foreground_sizes.items():
    d = os.path.join(base, folder)
    os.makedirs(d, exist_ok=True)
    resized = img.resize((size, size), Image.LANCZOS)
    resized.save(os.path.join(d, "ic_launcher_foreground.png"))
    print(f"✅ {folder}: foreground {size}x{size}")

print("🎉 Semua icon berhasil di-inject!")
