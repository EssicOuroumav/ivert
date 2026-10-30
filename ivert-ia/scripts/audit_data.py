"""Audit des jeux d'images IVERT.

Parcourt un dossier de données (par défaut data/raw), considère chaque dossier
qui contient directement des images comme une classe, puis :
  - compte les images par source / classe,
  - détecte les fichiers corrompus ou illisibles,
  - relève formats et dimensions,
  - repère les doublons exacts (MD5) et quasi-doublons (hash perceptuel),
    y compris entre sources différentes (risque de fuite train/test).

Sorties : reports/audit.json et reports/audit.md

Usage :
    python -I scripts/audit_data.py [dossier] [--seuil 4]
"""

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path

import imagehash
import numpy as np
from PIL import Image, UnidentifiedImageError

EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tif", ".tiff"}
RACINE = Path(__file__).resolve().parent.parent


def lister_images(dossier: Path):
    for chemin in sorted(dossier.rglob("*")):
        if chemin.is_file() and chemin.suffix.lower() in EXTENSIONS:
            yield chemin


def analyser_image(chemin: Path):
    """Retourne (infos, erreur). L'image est vérifiée puis entièrement décodée."""
    try:
        with Image.open(chemin) as img:
            img.verify()
        with Image.open(chemin) as img:
            img.load()
            infos = {
                "format": img.format,
                "largeur": img.width,
                "hauteur": img.height,
                "mode": img.mode,
                "phash": int(str(imagehash.phash(img.convert("RGB"))), 16),
            }
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError) as exc:
        return None, f"{type(exc).__name__}: {exc}"
    infos["md5"] = hashlib.md5(chemin.read_bytes()).hexdigest()
    return infos, None


def quasi_doublons(hashes: np.ndarray, seuil: int, bloc: int = 512):
    """Paires (i, j), i < j, dont la distance de Hamming des pHash est <= seuil."""
    paires = []
    n = len(hashes)
    for debut in range(0, n, bloc):
        fin = min(debut + bloc, n)
        dist = np.bitwise_count(hashes[debut:fin, None] ^ hashes[None, :])
        lignes, colonnes = np.nonzero(dist <= seuil)
        for i, j in zip(lignes + debut, colonnes):
            if i < j:
                paires.append((int(i), int(j), int(dist[i - debut, j])))
    return paires


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dossier", nargs="?", default=str(RACINE / "data" / "raw"))
    parser.add_argument("--seuil", type=int, default=2, help="distance pHash max pour un quasi-doublon")
    parser.add_argument("--sortie", default=str(RACINE / "reports"))
    args = parser.parse_args()

    base = Path(args.dossier).resolve()
    sortie = Path(args.sortie)
    sortie.mkdir(parents=True, exist_ok=True)

    images, corrompues = [], []
    formats, comptes = Counter(), defaultdict(Counter)

    chemins = list(lister_images(base))
    print(f"{len(chemins)} fichiers image trouvés dans {base}")
    for k, chemin in enumerate(chemins, 1):
        rel = chemin.relative_to(base)
        source = rel.parts[0] if len(rel.parts) > 1 else "."
        classe = str(rel.parent.relative_to(source)) if len(rel.parts) > 2 else rel.parent.name
        infos, erreur = analyser_image(chemin)
        if erreur:
            corrompues.append({"fichier": str(rel), "erreur": erreur})
            continue
        infos.update({"fichier": str(rel), "source": source, "classe": classe})
        images.append(infos)
        formats[infos["format"]] += 1
        comptes[source][classe] += 1
        if k % 500 == 0:
            print(f"  {k}/{len(chemins)}")

    # Doublons exacts
    par_md5 = defaultdict(list)
    for img in images:
        par_md5[img["md5"]].append(img["fichier"])
    doublons_exacts = [g for g in par_md5.values() if len(g) > 1]

    # Quasi-doublons
    hashes = np.array([img["phash"] for img in images], dtype=np.uint64)
    paires = quasi_doublons(hashes, args.seuil) if len(hashes) else []
    quasi = []
    inter_sources = 0
    conflits_classe = 0
    for i, j, d in paires:
        a, b = images[i], images[j]
        if a["md5"] == b["md5"]:
            continue
        entre_sources = a["source"] != b["source"]
        classe_diff = a["classe"] != b["classe"]
        inter_sources += entre_sources
        conflits_classe += classe_diff
        quasi.append({"a": a["fichier"], "b": b["fichier"], "distance": d,
                      "entre_sources": entre_sources, "classes_differentes": classe_diff})

    largeurs = [img["largeur"] for img in images]
    hauteurs = [img["hauteur"] for img in images]
    resume = {
        "dossier": str(base),
        "total_fichiers": len(chemins),
        "images_valides": len(images),
        "corrompues": len(corrompues),
        "formats": dict(formats),
        "dimensions": {
            "largeur_min": min(largeurs, default=0), "largeur_max": max(largeurs, default=0),
            "hauteur_min": min(hauteurs, default=0), "hauteur_max": max(hauteurs, default=0),
            "petites_<224px": sum(1 for w, h in zip(largeurs, hauteurs) if min(w, h) < 224),
        },
        "doublons_exacts_groupes": len(doublons_exacts),
        "doublons_exacts_fichiers_en_trop": sum(len(g) - 1 for g in doublons_exacts),
        "quasi_doublons_paires": len(quasi),
        "quasi_doublons_entre_sources": inter_sources,
        "quasi_doublons_classes_differentes": conflits_classe,
        "comptes": {s: dict(c) for s, c in comptes.items()},
    }

    (sortie / "audit.json").write_text(json.dumps({
        "resume": resume,
        "corrompues": corrompues,
        "doublons_exacts": doublons_exacts,
        "quasi_doublons": quasi,
    }, ensure_ascii=False, indent=2))

    lignes = [f"# Audit des données IVERT\n", f"Dossier : `{base}`\n",
              f"- Fichiers image : **{resume['total_fichiers']}**",
              f"- Valides : **{resume['images_valides']}** · corrompus : **{resume['corrompues']}**",
              f"- Formats : {', '.join(f'{k} {v}' for k, v in formats.most_common())}",
              f"- Dimensions : {resume['dimensions']}",
              f"- Doublons exacts : {resume['doublons_exacts_groupes']} groupes "
              f"({resume['doublons_exacts_fichiers_en_trop']} fichiers en trop)",
              f"- Quasi-doublons (pHash ≤ {args.seuil}) : {len(quasi)} paires, dont "
              f"{inter_sources} entre sources et {conflits_classe} avec des classes différentes\n"]
    for source, c in sorted(comptes.items()):
        lignes.append(f"## {source} — {sum(c.values())} images\n")
        lignes.append("| Classe | Images | Alerte |\n|---|---:|---|")
        for classe, n in sorted(c.items(), key=lambda x: -x[1]):
            alerte = "⚠️ < 300" if n < 300 else ""
            lignes.append(f"| {classe} | {n} | {alerte} |")
        lignes.append("")
    if corrompues:
        lignes.append("## Fichiers corrompus (20 premiers)\n")
        lignes += [f"- `{c['fichier']}` — {c['erreur']}" for c in corrompues[:20]]
    (sortie / "audit.md").write_text("\n".join(lignes) + "\n")

    print(json.dumps(resume, ensure_ascii=False, indent=2))
    print(f"\nRapports : {sortie / 'audit.md'} et {sortie / 'audit.json'}")


if __name__ == "__main__":
    main()
