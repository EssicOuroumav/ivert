"""Découpe les boîtes de détection en vignettes de classification.

Les jeux annotés en boîtes (Colombie YOLO, Amini, KaraAgro) servent ainsi aussi
au classifieur : chaque objet annoté (cabosse, feuille) devient une image
rangée dans un dossier à son nom de classe.

Formats :
  yolo : une image + un .txt de même nom ("classe cx cy w h", normalisés),
         noms de classes dans --noms (obj.names / classes.txt) ou --classes.
  csv  : un CSV avec Image_ID, class, xmin, ymin, xmax, ymax (format Zindi/Amini),
         images dans --images.

Usage :
    python -I scripts/crop_detections.py yolo SRC DEST [--noms obj.names | --classes a,b,c]
    python -I scripts/crop_detections.py csv Train.csv DEST --images DOSSIER_IMAGES
Options : --marge 0.15 (contexte ajouté autour de la boîte), --min-px 64
"""

import argparse
import csv
from collections import Counter
from pathlib import Path

from PIL import Image, ImageOps

EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def decouper(img, boite, marge, max_px):
    """boite = (x0, y0, x1, y1) en pixels ; ajoute une marge et borne à l'image."""
    x0, y0, x1, y1 = boite
    w, h = x1 - x0, y1 - y0
    x0, y0 = max(0, x0 - marge * w), max(0, y0 - marge * h)
    x1, y1 = min(img.width, x1 + marge * w), min(img.height, y1 + marge * h)
    vignette = img.crop((int(x0), int(y0), int(x1), int(y1)))
    vignette.thumbnail((max_px, max_px), Image.LANCZOS)
    return vignette


def lire_yolo(src, noms):
    for image in sorted(p for p in Path(src).rglob("*") if p.suffix.lower() in EXTENSIONS):
        etiquettes = image.with_suffix(".txt")
        if not etiquettes.exists():
            continue
        boites = []
        for ligne in etiquettes.read_text().split("\n"):
            parts = ligne.split()
            if len(parts) != 5:
                continue
            c, cx, cy, w, h = int(parts[0]), *map(float, parts[1:])
            boites.append((noms[c] if c < len(noms) else str(c), cx, cy, w, h))
        if boites:
            yield image, "norm", boites


def lire_csv(fichier, dossier_images):
    par_image = {}
    with open(fichier, newline="") as f:
        for r in csv.DictReader(f):
            par_image.setdefault(r["Image_ID"], []).append(
                (r["class"], float(r["xmin"]), float(r["ymin"]), float(r["xmax"]), float(r["ymax"])))
    index = {p.name: p for p in Path(dossier_images).rglob("*") if p.suffix.lower() in EXTENSIONS}
    index |= {p.stem: p for p in index.values()}
    for image_id, boites in par_image.items():
        image = index.get(image_id) or index.get(Path(image_id).stem)
        if image:
            yield image, "px", boites


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("format", choices=["yolo", "csv"])
    p.add_argument("src")
    p.add_argument("dest")
    p.add_argument("--noms", help="fichier des noms de classes (une par ligne)")
    p.add_argument("--classes", help="noms de classes séparés par des virgules")
    p.add_argument("--images", help="dossier des images (format csv)")
    p.add_argument("--marge", type=float, default=0.15)
    p.add_argument("--min-px", type=int, default=64)
    p.add_argument("--max-px", type=int, default=768)
    a = p.parse_args()

    if a.format == "yolo":
        noms = (Path(a.noms).read_text().split() if a.noms else a.classes.split(",") if a.classes else [])
        source = lire_yolo(a.src, noms)
    else:
        source = lire_csv(a.src, a.images)

    dest = Path(a.dest)
    comptes, trop_petites = Counter(), 0
    for image, mode, boites in source:
        with Image.open(image) as im:
            im = ImageOps.exif_transpose(im).convert("RGB")
            for k, b in enumerate(boites):
                if mode == "norm":
                    classe, cx, cy, w, h = b
                    boite = ((cx - w / 2) * im.width, (cy - h / 2) * im.height,
                             (cx + w / 2) * im.width, (cy + h / 2) * im.height)
                else:
                    classe, *boite = b
                if min(boite[2] - boite[0], boite[3] - boite[1]) < a.min_px:
                    trop_petites += 1
                    continue
                cible = dest / classe / f"{image.stem}_{k}.jpg"
                cible.parent.mkdir(parents=True, exist_ok=True)
                decouper(im, boite, a.marge, a.max_px).save(cible, "JPEG", quality=92)
                comptes[classe] += 1
    for c, n in comptes.most_common():
        print(f"{c:<30}{n:>6}")
    print(f"Ignorées (< {a.min_px} px) : {trop_petites}")


if __name__ == "__main__":
    main()
