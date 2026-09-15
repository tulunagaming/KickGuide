"""
Kopiert das Addon in den WoW-AddOns-Ordner (lokal testen, danach /reload im Spiel).

Aufruf:  python dev/install.py [Ziel-AddOns-Ordner]
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET_ADDONS = sys.argv[1] if len(sys.argv) > 1 else r"C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns"
FILES = ["KickGuide.toc", "Core.lua", "Data.lua", "Guide.lua", "LICENSE"]
FOLDERS = ["Libs"]

target = os.path.join(TARGET_ADDONS, "KickGuide")
os.makedirs(target, exist_ok=True)
for name in FILES:
    shutil.copy2(os.path.join(ROOT, name), os.path.join(target, name))
for name in FOLDERS:
    shutil.copytree(os.path.join(ROOT, name), os.path.join(target, name), dirs_exist_ok=True)
extra = sorted(set(os.listdir(target)) - set(FILES) - set(FOLDERS))
print("installiert nach", target)
if extra:
    print("Hinweis, im Zielordner liegen zusätzlich:", ", ".join(extra))
