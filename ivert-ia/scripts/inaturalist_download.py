"""Téléchargement des photos iNaturalist « qualité recherche » sous licence libre (CC0, CC BY, CC BY-SA).

Seules ces licences autorisent un usage commercial ; les licences NC/ND sont exclues photo par photo.
Chaque photo est enregistrée avec son auteur, sa licence et son observation dans attributions.csv
(attribution obligatoire).

Usage :
    python -I scripts/inaturalist_download.py --taxon 64340 --nom cacao
    python -I scripts/inaturalist_download.py --taxon 122988 --nom anacarde
"""

import argparse
import csv
import json
import time
import urllib.request
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
API = "https://api.inaturalist.org/v1/observations"
LICENCES = {"cc0", "cc-by", "cc-by-sa"}
ENTETES = {"User-Agent": "IVERT-collecte/1.0 (projet agricole, Cote d'Ivoire)"}


def get(url, binaire=False):
    for essai in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=ENTETES), timeout=60) as r:
                return r.read() if binaire else json.load(r)
        except Exception:
            if essai == 4:
                raise
            time.sleep(3 * (essai + 1))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--taxon", type=int, required=True)
    p.add_argument("--nom", required=True)
    p.add_argument("--taille", default="large", help="square, small, medium, large (1024 px), original")
    a = p.parse_args()

    dest = RACINE / "data" / "raw" / "inaturalist" / a.nom
    dest.mkdir(parents=True, exist_ok=True)
    lignes, id_min, page = [], None, 0
    while True:
        # Pagination par id décroissant (recommandée par l'API au-delà de 10 000 résultats)
        url = (f"{API}?taxon_id={a.taxon}&photos=true&quality_grade=research"
               f"&photo_license={','.join(sorted(LICENCES))}&per_page=200&order_by=id&order=desc")
        if id_min:
            url += f"&id_below={id_min}"
        res = get(url)["results"]
        if not res:
            break
        page += 1
        for obs in res:
            for photo in obs.get("photos", []):
                if photo.get("license_code") not in LICENCES:
                    continue
                fichier = dest / f"inat_{obs['id']}_{photo['id']}.jpg"
                if not fichier.exists():
                    fichier.write_bytes(get(photo["url"].replace("square", a.taille), binaire=True))
                    time.sleep(0.3)   # courtoisie envers le serveur
                lignes.append({
                    "fichier": fichier.name, "observation": f"https://www.inaturalist.org/observations/{obs['id']}",
                    "photo_id": photo["id"], "licence": photo["license_code"], "attribution": photo.get("attribution", ""),
                    "pays": (obs.get("place_guess") or "").split(",")[-1].strip(), "date": obs.get("observed_on") or "",
                })
        id_min = min(o["id"] for o in res)
        print(f"  page {page} : {len(lignes)} photos", flush=True)
        time.sleep(1)

    with open(dest / "attributions.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(lignes[0]))
        w.writeheader()
        w.writerows(lignes)
    print(f"Terminé : {len(lignes)} photos dans {dest}")


if __name__ == "__main__":
    main()
