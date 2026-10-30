"""Téléchargement sélectif d'un jeu Mendeley Data (dossier par dossier).

Évite de récupérer le zip complet quand seule une partie est utile
(ex. uniquement le cajou brut de CCMT).

Usage :
    # Lister l'arborescence et la taille de chaque dossier
    python -I scripts/mendeley_download.py bwh3zbpkpv 1 --lister
    # Télécharger les dossiers dont le chemin commence par un préfixe
    python -I scripts/mendeley_download.py bwh3zbpkpv 1 --dest data/raw/ccmt --inclure "Raw Data/CCMT Dataset/Cashew"
"""

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

API = "https://data.mendeley.com/public-api/datasets"
ENTETES = {"User-Agent": "curl/8.7.1", "Accept": "*/*"}


def ouvrir(url, timeout=60):
    return urllib.request.urlopen(urllib.request.Request(url, headers=ENTETES), timeout=timeout)


def get_json(url):
    for essai in range(4):
        try:
            with ouvrir(url) as r:
                return json.load(r)
        except Exception:
            if essai == 3:
                raise
            time.sleep(2 * (essai + 1))


def arborescence(ds, version):
    dossiers = get_json(f"{API}/{ds}/folders/{version}")
    par_id = {d["id"]: d for d in dossiers}

    def chemin(fid):
        parts = []
        while fid in par_id:
            parts.append(par_id[fid]["name"])
            fid = par_id[fid].get("parent_id")
        return "/".join(reversed(parts))

    return {fid: chemin(fid) for fid in par_id} | {"root": ""}


def fichiers(ds, version, folder_id):
    q = urllib.parse.urlencode({"folder_id": folder_id, "version": version})
    res = get_json(f"{API}/{ds}/files?{q}")
    return [f for f in res if isinstance(f, dict)]


def reduire(chemin: Path, max_px: int):
    """Réduit une photo (côté max = max_px), en appliquant l'orientation EXIF."""
    import subprocess
    from PIL import Image, ImageOps, UnidentifiedImageError
    sortie = chemin.with_suffix(".jpg")
    try:
        with Image.open(chemin) as img:
            img = ImageOps.exif_transpose(img).convert("RGB")
            img.thumbnail((max_px, max_px), Image.LANCZOS)
            img.save(sortie, "JPEG", quality=92)
    except (UnidentifiedImageError, OSError):
        # Formats non gérés par Pillow (DNG, HEIC…) : sips de macOS
        r = subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "92",
                            "-Z", str(max_px), str(chemin), "--out", str(sortie)],
                           capture_output=True)
        if r.returncode != 0 or not sortie.exists():
            print(f"  ⚠️ conversion impossible, original conservé : {chemin}", flush=True)
            return
    if chemin.suffix.lower() != ".jpg":
        chemin.unlink()


def telecharger(f, dest: Path, max_px=None):
    url = f["content_details"]["download_url"]
    taille = f.get("size") or f["content_details"].get("size", 0)
    if max_px and dest.with_suffix(".jpg").exists():
        return 0
    if not max_px and dest.exists() and dest.stat().st_size == taille:
        return 0
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    for essai in range(4):
        try:
            with ouvrir(url, timeout=300) as r, open(tmp, "wb") as out:
                while bloc := r.read(1 << 20):
                    out.write(bloc)
            tmp.rename(dest)
            if max_px:
                reduire(dest, max_px)
            return taille
        except Exception:
            if essai == 3:
                raise
            time.sleep(2 * (essai + 1))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("dataset")
    p.add_argument("version")
    p.add_argument("--lister", action="store_true")
    p.add_argument("--dest")
    p.add_argument("--inclure", action="append", default=[], help="préfixe de chemin à inclure (répétable)")
    p.add_argument("--threads", type=int, default=8)
    p.add_argument("--max-px", type=int, help="réduit chaque image à ce côté max après téléchargement")
    a = p.parse_args()

    chemins = arborescence(a.dataset, a.version)
    selection = [fid for fid, c in chemins.items()
                 if a.lister or any(c == pre or c.startswith(pre.rstrip("/") + "/") for pre in a.inclure)]

    with ThreadPoolExecutor(a.threads) as ex:
        listes = dict(zip(selection, ex.map(lambda fid: fichiers(a.dataset, a.version, fid), selection)))

    if a.lister:
        stats = defaultdict(lambda: [0, 0])
        for fid, fs in listes.items():
            for f in fs:
                stats[chemins[fid]][0] += 1
                stats[chemins[fid]][1] += f.get("size") or 0
        for c in sorted(stats):
            n, t = stats[c]
            print(f"{n:6d} fichiers {t / 1e6:9.1f} Mo  {c or '(racine)'}")
        return

    if not a.dest or not a.inclure:
        sys.exit("--dest et --inclure sont requis pour télécharger")
    taches = [(f, Path(a.dest) / chemins[fid] / f["filename"]) for fid, fs in listes.items() for f in fs]
    total = sum(f.get("size") or 0 for f, _ in taches)
    print(f"{len(taches)} fichiers, {total / 1e6:.1f} Mo → {a.dest}")
    with ThreadPoolExecutor(a.threads) as ex:
        for k, _ in enumerate(ex.map(lambda t: telecharger(*t, a.max_px), taches), 1):
            if k % 200 == 0 or k == len(taches):
                print(f"  {k}/{len(taches)}", flush=True)
    print("Terminé.")


if __name__ == "__main__":
    main()
