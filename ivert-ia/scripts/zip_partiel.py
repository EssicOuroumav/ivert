"""Extraction partielle d'un zip distant (requêtes HTTP Range).

Lit seulement le répertoire central du zip, puis les membres demandés :
on récupère par ex. le cajou brut de CCMT sans télécharger les 8,4 Go.

Usage :
    python -I scripts/zip_partiel.py URL --lister
    python -I scripts/zip_partiel.py URL --dest data/raw/ccmt --inclure "Raw Data/CCMT Dataset/Cashew/"
"""

import argparse
import io
import time
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path

ENTETES = {"User-Agent": "curl/8.7.1"}


class FichierHTTP(io.RawIOBase):
    """Fichier en lecture seule adossé à des requêtes Range.

    L'URL d'origine (ex. Mendeley) redirige vers une URL S3 signée qui expire :
    on la résout de nouveau en cas d'erreur.
    """

    def __init__(self, url):
        self.url_source = url
        self.pos = 0
        self._resoudre()

    def _resoudre(self):
        req = urllib.request.Request(self.url_source, headers={**ENTETES, "Range": "bytes=0-0"})
        with urllib.request.urlopen(req, timeout=60) as r:
            self.url = r.geturl()
            self.taille = int(r.headers["Content-Range"].split("/")[1])

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=io.SEEK_SET):
        base = {io.SEEK_SET: 0, io.SEEK_CUR: self.pos, io.SEEK_END: self.taille}[whence]
        self.pos = base + offset
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.taille - self.pos
        if n == 0 or self.pos >= self.taille:
            return b""
        fin = min(self.pos + n, self.taille) - 1
        for essai in range(5):
            try:
                req = urllib.request.Request(self.url, headers={**ENTETES, "Range": f"bytes={self.pos}-{fin}"})
                with urllib.request.urlopen(req, timeout=120) as r:
                    data = r.read()
                break
            except Exception:
                if essai == 4:
                    raise
                time.sleep(2 * (essai + 1))
                self._resoudre()
        self.pos += len(data)
        return data

    def readinto(self, b):
        data = self.read(len(b))
        b[:len(data)] = data
        return len(data)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("url")
    p.add_argument("--lister", action="store_true")
    p.add_argument("--dest")
    p.add_argument("--inclure", action="append", default=[])
    a = p.parse_args()

    distant = FichierHTTP(a.url)
    print(f"Zip distant : {distant.taille / 1e9:.2f} Go")
    zf = zipfile.ZipFile(io.BufferedReader(distant, buffer_size=1 << 20))
    membres = [m for m in zf.infolist() if not m.is_dir()]

    if a.lister:
        stats = defaultdict(lambda: [0, 0])
        for m in membres:
            d = str(Path(m.filename).parent)
            stats[d][0] += 1
            stats[d][1] += m.compress_size
        for d in sorted(stats):
            print(f"{stats[d][0]:6d} fichiers {stats[d][1] / 1e6:9.1f} Mo  {d}")
        return

    choisis = [m for m in membres if any(m.filename.startswith(pre) for pre in a.inclure)]
    total = sum(m.compress_size for m in choisis)
    print(f"{len(choisis)} fichiers, {total / 1e6:.1f} Mo → {a.dest}")
    dest = Path(a.dest).resolve()
    for k, m in enumerate(choisis, 1):
        cible = (dest / m.filename).resolve()
        if dest not in cible.parents:
            raise SystemExit(f"Chemin suspect refusé : {m.filename}")
        if cible.exists() and cible.stat().st_size == m.file_size:
            continue
        cible.parent.mkdir(parents=True, exist_ok=True)
        with zf.open(m) as src, open(cible, "wb") as out:
            out.write(src.read())
        if k % 200 == 0 or k == len(choisis):
            print(f"  {k}/{len(choisis)}", flush=True)
    print("Terminé.")


if __name__ == "__main__":
    main()
