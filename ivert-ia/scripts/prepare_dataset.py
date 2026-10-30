"""Construit le jeu de classification propre à partir de data/raw.

1. Associe chaque dossier source à (culture, classe, organe) via data/labels_map.csv
   (motifs glob relatifs à data/raw/<source>/ ; classe IGNORER = exclu).
2. Écarte les doublons exacts (MD5) et regroupe les quasi-doublons (pHash)
   pour qu'un même sujet ne soit jamais à la fois en train et en test.
3. Découpe 70/15/15 stratifié par classe, au niveau des groupes.
4. Écrit des copies réduites (côté max 512 px) dans
   data/clean/<culture>/<split>/<classe>/ + data/clean/<culture>/manifest.csv
5. Optionnel (--zip) : archive data/clean/<culture>.zip à envoyer sur Colab/Kaggle.

Usage :
    python -I scripts/prepare_dataset.py [--culture cacao] [--seuil-groupe 6] [--zip]
"""

import argparse
import csv
import fnmatch
import hashlib
import random
import re
import shutil
from collections import Counter, defaultdict
from pathlib import Path

import imagehash
import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError

RACINE = Path(__file__).resolve().parent.parent
RAW = RACINE / "data" / "raw"
CLEAN = RACINE / "data" / "clean"
EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
PARTS = {"train": 0.70, "val": 0.15, "test": 0.15}


def charger_map(chemin):
    with open(chemin, newline="") as f:
        return list(csv.DictReader(f))


def etiqueter(source, rel_dossier, regles, culture):
    """Première règle qui correspond pour cette culture (un même dossier peut servir
    à deux cultures, ex. feuilles d'anacarde = « autre » pour le modèle cacao).
    Renvoie None si aucune règle ne mentionne ce dossier, {} s'il n'est pas utilisé pour cette culture."""
    vu = False
    for r in regles:
        if r["source"] == source and fnmatch.fnmatch(rel_dossier, r["motif"]):
            vu = True
            if r["culture"] == culture:
                return r
    return {} if vu else None


class UnionFind:
    def __init__(self, n):
        self.p = list(range(n))

    def find(self, x):
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]
            x = self.p[x]
        return x

    def union(self, a, b):
        self.p[self.find(a)] = self.find(b)


def grouper(hashes, seuil, bloc=512):
    uf = UnionFind(len(hashes))
    for debut in range(0, len(hashes), bloc):
        dist = np.bitwise_count(hashes[debut:debut + bloc, None] ^ hashes[None, :])
        for i, j in zip(*np.nonzero(dist <= seuil)):
            if i + debut < j:
                uf.union(i + debut, j)
    return [uf.find(i) for i in range(len(hashes))]


def decouper(groupes_par_classe, graine):
    """Répartit les groupes de chaque classe en train/val/test.

    Les groupes (du plus gros au plus petit, ordre aléatoire à taille égale) vont
    au split le plus en retard sur sa cible : proportions respectées malgré les gros groupes.
    """
    rng = random.Random(graine)
    affectation = {}
    for classe, groupes in groupes_par_classe.items():
        items = list(groupes.items())
        rng.shuffle(items)
        items.sort(key=lambda kv: -len(kv[1]))
        total = sum(len(v) for _, v in items)
        rempli = Counter()
        for gid, membres in items:
            split = max(PARTS, key=lambda s: PARTS[s] * total - rempli[s])
            affectation[gid] = split
            rempli[split] += len(membres)
    return affectation


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--culture", choices=["cacao", "anacarde"], action="append")
    p.add_argument("--seuil-groupe", type=int, default=6, help="distance pHash pour regrouper des photos du même sujet")
    p.add_argument("--seuil-conflit", type=int, default=2, help="distance pHash d'une quasi-copie")
    p.add_argument("--max-px", type=int, default=512)
    p.add_argument("--graine", type=int, default=42)
    p.add_argument("--zip", action="store_true")
    a = p.parse_args()
    cultures = a.culture or ["cacao", "anacarde"]
    regles = charger_map(RACINE / "data" / "labels_map.csv")

    for culture in cultures:
        print(f"\n=== {culture} ===")
        images, non_mappes = [], Counter()
        for source_dir in sorted(d for d in RAW.iterdir() if d.is_dir()):
            for f in sorted(source_dir.rglob("*")):
                if not (f.is_file() and f.suffix.lower() in EXTENSIONS):
                    continue
                rel = str(f.parent.relative_to(source_dir))
                r = etiqueter(source_dir.name, rel, regles, culture)
                if r is None:
                    non_mappes[f"{source_dir.name}/{rel}"] += 1
                    continue
                if not r or r["classe"] == "IGNORER":
                    continue
                img = {"chemin": f, "source": source_dir.name, "classe": r["classe"], "organe": r["organe"],
                       "regle": (r["source"], r["motif"]), "max": int(r.get("max") or 0)}
                # Vignettes découpées d'une même photo (<photo>_<k>.jpg) : même split imposé, toutes classes confondues
                m = re.fullmatch(r"(.+)_\d+", f.stem)
                if source_dir.name.endswith("_crops") and m:
                    h = int(hashlib.md5(f"{source_dir.name}/{m.group(1)}".encode()).hexdigest(), 16) % 100
                    img["split_force"] = "train" if h < 70 else "val" if h < 85 else "test"
                images.append(img)
        for d, n in non_mappes.items():
            print(f"  ⚠️ non mappé ({n} images) : {d}")
        # HORS_SUJET : photos qui ne sont pas la culture cible, JAMAIS utilisées pour l'entraînement,
        # seulement pour mesurer le rejet par ressemblance (dossier hors_sujet/ du zip)
        hors_sujet = [i for i in images if i["classe"] == "HORS_SUJET"]
        images = [i for i in images if i["classe"] != "HORS_SUJET"]
        # Plafond par règle (colonne « max » de labels_map.csv), tirage reproductible
        par_regle = defaultdict(list)
        for img in images + hors_sujet:
            par_regle[img["regle"]].append(img)
        rng = random.Random(a.graine)
        images, hors_sujet = [], []
        for regle, liste in par_regle.items():
            plafond = liste[0]["max"]
            if plafond and len(liste) > plafond:
                print(f"  plafond {regle[0]}/{regle[1]} : {plafond} sur {len(liste)}")
                liste = rng.sample(liste, plafond)
            (hors_sujet if liste[0]["classe"] == "HORS_SUJET" else images).extend(liste)
        if not images:
            print("  aucune image")
            continue

        # Hash + dédoublonnage exact
        vus, uniques = set(), []
        for img in images:
            try:
                with Image.open(img["chemin"]) as im:
                    im = ImageOps.exif_transpose(im).convert("RGB")
                    img["phash"] = int(str(imagehash.phash(im)), 16)
            except (UnidentifiedImageError, OSError):
                continue
            md5 = hashlib.md5(img["chemin"].read_bytes()).hexdigest()
            if md5 in vus:
                continue
            vus.add(md5)
            uniques.append(img)
        print(f"  {len(images)} images mappées, {len(uniques)} après dédoublonnage exact")

        hashes = np.array([i["phash"] for i in uniques], dtype=np.uint64)
        # Quasi-copies (seuil strict) présentes dans plusieurs classes = étiquettes contradictoires : écartées
        stricts = grouper(hashes, a.seuil_conflit)
        classes_strict = defaultdict(set)
        for img, g in zip(uniques, stricts):
            classes_strict[g].add(img["classe"])
        conflits = {g for g, c in classes_strict.items() if len(c) > 1}
        if conflits:
            avant = len(uniques)
            garder = [g not in conflits for g in stricts]
            uniques = [img for img, ok in zip(uniques, garder) if ok]
            hashes = hashes[np.array(garder)]
            print(f"  ⚠️ {len(conflits)} quasi-copies aux étiquettes contradictoires écartées ({avant - len(uniques)} images)")
        # Regroupement plus large pour le découpage : photos d'un même sujet dans le même split
        par_classe = defaultdict(lambda: defaultdict(list))
        for img, g in zip(uniques, grouper(hashes, a.seuil_groupe)):
            img["groupe"] = g
            par_classe[img["classe"]][g].append(img)
        affectation = decouper(par_classe, a.graine)

        sortie = CLEAN / culture
        if sortie.exists():
            shutil.rmtree(sortie)
        lignes, stats = [], defaultdict(Counter)
        for classe, groupes_c in par_classe.items():
            for g, membres in groupes_c.items():
                for img in membres:
                    split = img.get("split_force") or affectation[g]
                    nom = f"{img['source']}__{hashlib.md5(str(img['chemin']).encode()).hexdigest()[:10]}.jpg"
                    cible = sortie / split / classe / nom
                    cible.parent.mkdir(parents=True, exist_ok=True)
                    with Image.open(img["chemin"]) as im:
                        im = ImageOps.exif_transpose(im).convert("RGB")
                        im.thumbnail((a.max_px, a.max_px), Image.LANCZOS)
                        im.save(cible, "JPEG", quality=90)
                    stats[classe][split] += 1
                    lignes.append({"fichier": str(cible.relative_to(sortie)), "split": split, "classe": classe,
                                   "organe": img["organe"], "source": img["source"], "groupe": g,
                                   "origine": str(img["chemin"].relative_to(RAW))})
        for img in hors_sujet:
            cible = sortie / "hors_sujet" / f"{img['source']}__{hashlib.md5(str(img['chemin']).encode()).hexdigest()[:10]}.jpg"
            cible.parent.mkdir(parents=True, exist_ok=True)
            try:
                with Image.open(img["chemin"]) as im:
                    im = ImageOps.exif_transpose(im).convert("RGB")
                    im.thumbnail((a.max_px, a.max_px), Image.LANCZOS)
                    im.save(cible, "JPEG", quality=90)
            except (UnidentifiedImageError, OSError):
                print(f"  ⚠️ image illisible ignorée : {img['chemin'].name}")
        print(f"  hors_sujet (évaluation du rejet uniquement) : {len(hors_sujet)} images")
        with open(sortie / "manifest.csv", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(lignes[0]))
            w.writeheader()
            w.writerows(lignes)

        print(f"  {'classe':<16}{'train':>7}{'val':>7}{'test':>7}{'total':>8}")
        for classe in sorted(stats):
            s = stats[classe]
            print(f"  {classe:<16}{s['train']:>7}{s['val']:>7}{s['test']:>7}{sum(s.values()):>8}")
        if a.zip:
            archive = shutil.make_archive(str(CLEAN / culture), "zip", sortie)
            print(f"  archive : {archive} ({Path(archive).stat().st_size / 1e6:.0f} Mo)")


if __name__ == "__main__":
    main()
