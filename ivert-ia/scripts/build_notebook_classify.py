"""Génère notebooks/train_classify.ipynb (Colab / Kaggle, GPU).

Le notebook est généré depuis ce script pour rester relisible et versionnable.
Usage : python -I scripts/build_notebook_classify.py
"""

import json
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
cellules = []


def md(texte):
    cellules.append({"cell_type": "markdown", "metadata": {}, "source": texte.strip("\n")})


def code(texte):
    cellules.append({"cell_type": "code", "metadata": {}, "execution_count": None, "outputs": [],
                     "source": texte.strip("\n")})


md("""
# IVERT : entraînement du classifieur de maladies (cacao / anacarde)

Transfert d'apprentissage (MobileNetV3 / EfficientNetV2, poids ImageNet), puis export **TFLite** pour l'app Flutter hors ligne.

**Avant de lancer** : Exécution → Modifier le type d'exécution → **GPU**.

1. Mets `SMOKE = True` et lance tout (environ 5 min) pour vérifier le pipeline.
2. Puis `SMOKE = False` pour le vrai entraînement (environ 30 à 60 min).
3. Télécharge `ivert_<culture>_classify_<VERSION>.zip` à la fin et dépose-le dans `ivert-ia/models/`.
""")

code("""
# ==== PARAMÈTRES ====
CULTURE = "cacao"             # "cacao" ou "anacarde"
SMOKE = False                 # True = test rapide du pipeline, False = vrai entraînement
BACKBONE = "mobilenet_v3_large"   # "mobilenet_v3_large" (léger, rapide) ou "efficientnet_v2_b0" (plus précis, plus lourd)
IMG = 224
BATCH = 32
EPOCHS_TETE = 2 if SMOKE else 12
EPOCHS_FINE = 1 if SMOKE else 25
SEUIL_PRECISION_CIBLE = 0.95  # précision visée sur les diagnostics acceptés (le reste → « non reconnu »)
VERSION = "v3"
REPRENDRE = True              # True = si un modèle déjà entraîné existe sur cette machine Colab, on le réutilise (pas de nouvel entraînement)
""")

md("## 1. Environnement")
code("""
import os, sys, json, zipfile, shutil, glob, random, time
import numpy as np
import tensorflow as tf
print("TensorFlow", tf.__version__, "| Python", sys.version.split()[0])
print("GPU :", tf.config.list_physical_devices("GPU") or "AUCUN (active le GPU !)")
tf.keras.utils.set_random_seed(42)
EN_COLAB = "google.colab" in sys.modules
EN_KAGGLE = os.path.exists("/kaggle")
TRAVAIL = "/kaggle/working" if EN_KAGGLE else "/content"
""")

md("""
## 2. Données

Le zip `<culture>.zip` est produit en local par `scripts/prepare_dataset.py --zip` (dossiers `train/ val/ test/` + `manifest.csv`).

- **Colab** : dépose-le dans Google Drive, dans `MonDrive/IVERT/`.
- **Kaggle** : crée un dataset privé `ivert-<culture>` contenant le zip.
""")
code("""
if EN_COLAB:
    from google.colab import drive
    drive.mount("/content/drive")
    candidats = glob.glob(f"/content/drive/MyDrive/IVERT/{CULTURE}.zip")
else:
    candidats = glob.glob(f"/kaggle/input/**/{CULTURE}.zip", recursive=True) + glob.glob(f"/kaggle/input/**/{CULTURE}/train", recursive=True)
assert candidats, f"Zip introuvable pour {CULTURE}"
DATA = f"{TRAVAIL}/data_{CULTURE}"
if candidats[0].endswith(".zip"):
    shutil.rmtree(DATA, ignore_errors=True)
    with zipfile.ZipFile(candidats[0]) as z:
        z.extractall(DATA)
else:
    DATA = os.path.dirname(candidats[0])
for split in ("train", "val", "test"):
    n = len(glob.glob(f"{DATA}/{split}/*/*.jpg"))
    print(split, n, "images")
""")

code("""
def charger(split, melanger):
    ds = tf.keras.utils.image_dataset_from_directory(
        f"{DATA}/{split}", image_size=(IMG, IMG), batch_size=BATCH,
        label_mode="int", shuffle=melanger, seed=42)
    return ds

train_ds = charger("train", True)
CLASSES = train_ds.class_names
val_ds = charger("val", False)
test_ds = charger("test", False)
assert val_ds.class_names == CLASSES == test_ds.class_names
print("Classes :", CLASSES)

if SMOKE:
    train_ds = train_ds.take(10); val_ds = val_ds.take(4); test_ds = test_ds.take(4)

# Poids de classes (classes rares comme la gommose)
comptes = np.array([len(glob.glob(f"{DATA}/train/{c}/*.jpg")) for c in CLASSES], dtype=float)
poids = {i: float(comptes.sum() / (len(CLASSES) * n)) for i, n in enumerate(comptes)}
print("Poids de classes :", {CLASSES[i]: round(p, 2) for i, p in poids.items()})

AUTOTUNE = tf.data.AUTOTUNE
train_ds = train_ds.prefetch(AUTOTUNE); val_ds = val_ds.cache().prefetch(AUTOTUNE); test_ds = test_ds.cache().prefetch(AUTOTUNE)
""")

md("""
## 3. Modèle

Augmentations proches du terrain : cadrage, rotation, lumière, contraste et flou.
L'entrée du modèle est l'image **RGB 0-255** (le prétraitement est inclus dans le modèle), ce qui simplifie l'app Flutter.
""")
code("""
augment = tf.keras.Sequential([
    tf.keras.layers.RandomFlip("horizontal_and_vertical"),
    tf.keras.layers.RandomRotation(0.2),
    tf.keras.layers.RandomZoom((-0.1, 0.3)),
    tf.keras.layers.RandomTranslation(0.1, 0.1),
    tf.keras.layers.RandomBrightness(0.25, value_range=(0, 255)),
    tf.keras.layers.RandomContrast(0.25),
], name="augmentation")

def construire_base():
    if BACKBONE == "mobilenet_v3_large":
        return tf.keras.applications.MobileNetV3Large(input_shape=(IMG, IMG, 3), include_top=False,
                                                      weights="imagenet", include_preprocessing=True)
    if BACKBONE == "efficientnet_v2_b0":
        return tf.keras.applications.EfficientNetV2B0(input_shape=(IMG, IMG, 3), include_top=False,
                                                      weights="imagenet", include_preprocessing=True)
    raise ValueError(BACKBONE)

base = construire_base()
base.trainable = False
entree = tf.keras.Input((IMG, IMG, 3), name="image")
x = augment(entree)
x = base(x, training=False)          # BatchNorm figés, y compris pendant l'affinage
x = tf.keras.layers.GlobalAveragePooling2D()(x)
x = tf.keras.layers.Dropout(0.3)(x)
sortie = tf.keras.layers.Dense(len(CLASSES), activation="softmax", name="probas")(x)
modele = tf.keras.Model(entree, sortie)
modele.summary(show_trainable=True)
""")

md("## 4. Entraînement en 2 temps : tête, puis affinage")
code("""
CKPT = f"{TRAVAIL}/meilleur_{CULTURE}_{VERSION}{'_smoke' if SMOKE else ''}.keras"
def rappels(patience):
    return [
        tf.keras.callbacks.ModelCheckpoint(CKPT, monitor="val_accuracy", save_best_only=True),
        tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=patience, restore_best_weights=True),
        tf.keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.3, patience=max(1, patience // 2)),
    ]

h1 = h2 = None
# Ancien nom de sauvegarde (avant la reprise) : accepté seulement s'il a le bon nombre de classes
ANCIEN = f"{TRAVAIL}/meilleur_{CULTURE}.keras"
if REPRENDRE and not SMOKE and not os.path.exists(CKPT) and os.path.exists(ANCIEN):
    if tf.keras.models.load_model(ANCIEN).output_shape[-1] == len(CLASSES):
        shutil.copy(ANCIEN, CKPT)
if REPRENDRE and os.path.exists(CKPT):
    print("♻️ Modèle déjà entraîné trouvé, entraînement sauté :", CKPT)
    modele = tf.keras.models.load_model(CKPT)
else:
  modele.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
               loss="sparse_categorical_crossentropy", metrics=["accuracy"])
  h1 = modele.fit(train_ds, validation_data=val_ds, epochs=EPOCHS_TETE, class_weight=poids, callbacks=rappels(4))

  # Affinage : on dégèle le dernier tiers du backbone
  base.trainable = True
  gel = int(len(base.layers) * 2 / 3)
  for couche in base.layers[:gel]:
      couche.trainable = False
  for couche in base.layers:
      if isinstance(couche, tf.keras.layers.BatchNormalization):
          couche.trainable = False
  modele.compile(optimizer=tf.keras.optimizers.Adam(1e-5),
               loss="sparse_categorical_crossentropy", metrics=["accuracy"])
  h2 = modele.fit(train_ds, validation_data=val_ds, epochs=EPOCHS_FINE, class_weight=poids, callbacks=rappels(6))
  modele = tf.keras.models.load_model(CKPT)
""")

code("""
import matplotlib.pyplot as plt
if h1 is None:
    print("Courbes indisponibles (modèle repris)")
else:
  hist = {k: h1.history[k] + h2.history.get(k, []) for k in h1.history}
  fig, ax = plt.subplots(1, 2, figsize=(12, 4))
  for k in ("accuracy", "val_accuracy"): ax[0].plot(hist[k], label=k)
  for k in ("loss", "val_loss"): ax[1].plot(hist[k], label=k)
  for a in ax: a.axvline(len(h1.history["loss"]) - 0.5, ls="--", c="gray"); a.legend()
  plt.show()
""")

md("## 5. Évaluation sur le jeu de test (images jamais vues)")
code("""
from sklearn.metrics import classification_report, confusion_matrix, ConfusionMatrixDisplay
y_vrai = np.concatenate([y.numpy() for _, y in test_ds])
probas = modele.predict(test_ds, verbose=0)
y_pred = probas.argmax(1)
rapport = classification_report(y_vrai, y_pred, labels=range(len(CLASSES)), target_names=CLASSES, digits=3, output_dict=True, zero_division=0)
print(classification_report(y_vrai, y_pred, labels=range(len(CLASSES)), target_names=CLASSES, digits=3, zero_division=0))
cm = confusion_matrix(y_vrai, y_pred, labels=range(len(CLASSES)))
ConfusionMatrixDisplay(cm, display_labels=CLASSES).plot(xticks_rotation=45, cmap="Greens")
plt.title(f"Matrice de confusion — {CULTURE}"); plt.show()

GO = {c: rapport[c]["f1-score"] >= 0.80 for c in CLASSES}
print("Go/no-go (F1 ≥ 0,80) :", GO)
""")

md("### Score par source (le sous-ensemble ivoirien est le vrai indicateur terrain)")
code("""
import pandas as pd
chemins_test = [p for p in tf.keras.utils.image_dataset_from_directory(f"{DATA}/test", image_size=(IMG, IMG), shuffle=False, batch_size=BATCH).file_paths]
if SMOKE: chemins_test = chemins_test[:len(y_vrai)]
manifest = pd.read_csv(f"{DATA}/manifest.csv")
manifest["nom"] = manifest["fichier"].str.split("/").str[-1]
df = pd.DataFrame({"nom": [os.path.basename(p) for p in chemins_test], "vrai": y_vrai, "pred": y_pred,
                   "confiance": probas.max(1)})
df = df.merge(manifest[["nom", "source", "organe"]], on="nom", how="left")
df["correct"] = df.vrai == df.pred
print(df.groupby("source")["correct"].agg(["mean", "count"]).rename(columns={"mean": "précision"}))
""")

md("### Les erreurs les plus confiantes")
code("""
from PIL import Image
erreurs = df[~df.correct].sort_values("confiance", ascending=False).head(12)
fig, axes = plt.subplots(3, 4, figsize=(14, 11))
for a in axes.flat: a.axis("off")
for a, (_, r) in zip(axes.flat, erreurs.iterrows()):
    chemin = next(p for p in chemins_test if os.path.basename(p) == r.nom)
    a.imshow(Image.open(chemin)); a.set_title(f"vrai {CLASSES[r.vrai]}\\nprédit {CLASSES[r.pred]} ({r.confiance:.0%})", fontsize=9)
plt.tight_layout(); plt.show()
""")

md("""
### Seuil de confiance → « non reconnu »

En dessous du seuil, l'app répond « Diagnostic incertain, reprenez la photo ou consultez un expert » au lieu de risquer un faux diagnostic.
""")
code("""
seuils = np.linspace(0.3, 0.99, 70)
couverture, precision = [], []
conf_val = df.confiance.values; ok = df.correct.values
for s in seuils:
    garde = conf_val >= s
    couverture.append(garde.mean()); precision.append(ok[garde].mean() if garde.any() else 1.0)
couverture, precision = np.array(couverture), np.array(precision)
valides = np.where(precision >= SEUIL_PRECISION_CIBLE)[0]
SEUIL = float(seuils[valides[0]]) if len(valides) else 0.9
probables = np.where(precision >= 0.80)[0]
SEUIL_PROBABLE_BRUT = float(seuils[probables[0]]) if len(probables) else 0.5
# Bornes de prudence pour le terrain : jamais « certain » sous 60 %, jamais « probable » sous 40 %
SEUIL_CERTAIN = max(SEUIL, 0.60)
SEUIL_PROBABLE = min(max(SEUIL_PROBABLE_BRUT, 0.40), SEUIL_CERTAIN)
print(f"App : certain ≥ {SEUIL_CERTAIN:.2f} | probable ≥ {SEUIL_PROBABLE:.2f} | sinon incertain")
i = int(np.argmin(abs(seuils - SEUIL)))
print(f"Seuil retenu : {SEUIL:.2f} → précision {precision[i]:.1%} sur {couverture[i]:.1%} des photos acceptées")
plt.plot(seuils, precision, label="précision des acceptés"); plt.plot(seuils, couverture, label="part acceptée")
plt.axvline(SEUIL, ls="--", c="gray"); plt.legend(); plt.xlabel("seuil de confiance"); plt.show()
""")

md("""
## 5 bis. Rejet par ressemblance (« ce n'est pas du cacao / de l'anacarde »)

Le modèle n'apprend **que** la culture cible. Pour rejeter le reste, on garde des **empreintes** (prototypes) des vraies photos d'entraînement :
si une photo est trop éloignée de toutes les empreintes, l'app la rejette.
Le dossier `hors_sujet/` (autres plantes, photos de l'utilisateur) sert **uniquement à mesurer** ce rejet, jamais à l'entraînement.
""")
code("""
from sklearn.cluster import KMeans

# Modèle d'inférence sans augmentation + extracteur d'empreinte (sortie du GlobalAveragePooling)
inf_in = tf.keras.Input((IMG, IMG, 3), name="image")
x = inf_in
for couche in modele.layers[1:]:
    if couche.name == "augmentation": continue
    x = couche(x)
    if isinstance(couche, tf.keras.layers.GlobalAveragePooling2D):
        empreinte = x
modele_inf = tf.keras.Model(inf_in, x)
extracteur = tf.keras.Model(inf_in, empreinte)
DIM = int(empreinte.shape[-1])

def empreintes(ds):
    e = extracteur.predict(ds, verbose=0)
    return e / np.linalg.norm(e, axis=1, keepdims=True)

# Mélangé (graine fixe) : en mode SMOKE, les 10 lots contiennent ainsi toutes les classes.
# Une seule passe, lot par lot : on ne garde en mémoire que les empreintes (pas les photos).
train_fixe = tf.keras.utils.image_dataset_from_directory(f"{DATA}/train", image_size=(IMG, IMG), batch_size=BATCH,
                                                         label_mode="int", shuffle=True, seed=7)
if SMOKE: train_fixe = train_fixe.take(10)
e_lots, y_lots = [], []
for images, y in train_fixe:
    e_lots.append(extracteur(images, training=False).numpy()); y_lots.append(y.numpy())
e_train = np.concatenate(e_lots); e_train /= np.linalg.norm(e_train, axis=1, keepdims=True)
y_train = np.concatenate(y_lots)
del e_lots, y_lots

K_PAR_CLASSE = 32
prototypes = []
for c in range(len(CLASSES)):
    ec = e_train[y_train == c]
    if len(ec) == 0:
        print(f"⚠️ aucune photo pour {CLASSES[c]} (normal seulement en SMOKE)"); continue
    k = max(1, min(K_PAR_CLASSE, len(ec) // 10, len(ec)))
    centres = KMeans(n_clusters=k, n_init=4, random_state=42).fit(ec).cluster_centers_
    prototypes.append(centres / np.linalg.norm(centres, axis=1, keepdims=True))
prototypes = np.concatenate(prototypes).astype(np.float32)
print("Prototypes :", prototypes.shape)

def ressemblance(e):
    return (e @ prototypes.T).max(axis=1)

# Seuil : on accepte 97 % des vraies photos de validation de la culture
s_val = ressemblance(empreintes(val_ds))
SEUIL_OOD = float(np.percentile(s_val, 3))
s_test = ressemblance(empreintes(test_ds))
print(f"Seuil de ressemblance : {SEUIL_OOD:.3f} | vraies photos test acceptées : {(s_test >= SEUIL_OOD).mean():.1%}")

OOD = {"seuil": SEUIL_OOD, "dim": DIM, "nb_prototypes": int(len(prototypes)),
       "test_acceptees": float((s_test >= SEUIL_OOD).mean())}
hs = sorted(glob.glob(f"{DATA}/hors_sujet/*.jpg"))
if hs:
    e_hs = []
    for i in range(0, len(hs), 64):   # par paquets de 64 pour ménager la RAM
        lot = np.stack([tf.keras.utils.img_to_array(tf.keras.utils.load_img(f, target_size=(IMG, IMG), interpolation="bilinear")) for f in hs[i:i + 64]])
        e_hs.append(extracteur(lot, training=False).numpy())
    e_hs = np.concatenate(e_hs); e_hs /= np.linalg.norm(e_hs, axis=1, keepdims=True)
    s_hs = ressemblance(e_hs)
    rejet = s_hs < SEUIL_OOD
    OOD["hors_sujet_rejetes"] = float(rejet.mean())
    print(f"Photos hors sujet rejetées : {rejet.mean():.1%} sur {len(hs)}")
    for f, s, r in zip(hs, s_hs, rejet):
        if "photos_utilisateur" in os.path.basename(f):
            print(f"  photo utilisateur {os.path.basename(f)} : ressemblance {s:.3f} → {'REJETÉE ✅' if r else 'acceptée ❌'}")
    plt.hist(s_val, bins=40, alpha=.6, label="vraies photos (val)"); plt.hist(s_hs, bins=40, alpha=.6, label="hors sujet")
    plt.axvline(SEUIL_OOD, c="k", ls="--"); plt.legend(); plt.title("Ressemblance aux empreintes"); plt.show()
""")

md("""
## 6. Export TFLite + vérification de cohérence

- **fp16** (environ 6 Mo) : modèle principal de l'app, fidèle au modèle d'origine.
- **dyn** (environ 3 Mo) : poids compressés en int8, calculs en float. Version de secours plus légère, gardée seulement si elle reste fidèle.

La quantification int8 « complète » est écartée : elle dégrade fortement MobileNetV3 et elle est refusée par XNNPACK.
""")
code("""
EXPORT = f"{TRAVAIL}/ivert_{CULTURE}_classify_{VERSION}"
shutil.rmtree(EXPORT, ignore_errors=True); os.makedirs(EXPORT)

# Sortie unique [1, NB_CLASSES + DIM] : probabilités puis empreinte normalisée (pour le rejet dans l'app)
modele_double = tf.keras.Model(inf_in, [modele_inf.outputs[0], extracteur.outputs[0]])

# Forme d'entrée FIXE [1, 224, 224, 3] : indispensable pour le délégué XNNPACK (utilisé aussi sur Android)
@tf.function(input_signature=[tf.TensorSpec([1, IMG, IMG, 3], tf.float32, name="image")])
def servir(image):
    probas, e = modele_double(image, training=False)
    return tf.concat([probas, tf.math.l2_normalize(e, axis=1)], axis=1)
# On « fige » les poids dans le graphe : sans ça, le .tflite ne contient pas les poids appris
from tensorflow.python.framework.convert_to_constants import convert_variables_to_constants_v2
fonction = convert_variables_to_constants_v2(servir.get_concrete_function())

def convertir(mode):
    conv = tf.lite.TFLiteConverter.from_concrete_functions([fonction])
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    if mode == "fp16":
        conv.target_spec.supported_types = [tf.float16]
    # mode "dyn" : Optimize.DEFAULT seul = quantification dynamique (poids int8, calculs float)
    return conv.convert()

MODES = ("fp16", "dyn")
for mode in MODES:
    data = convertir(mode)
    with open(f"{EXPORT}/{CULTURE}_classify_{VERSION}_{mode}.tflite", "wb") as f: f.write(data)
    print(mode, f"{len(data) / 1e6:.2f} Mo")
    assert len(data) > 1e6, f"{mode} : fichier trop petit ({len(data) / 1e6:.2f} Mo), les poids n'ont pas été inclus"
""")

code("""
import warnings; warnings.filterwarnings("ignore", message=".*tf.lite.Interpreter is deprecated.*")
def interpreteur(chemin):
    # D'abord comme sur le téléphone (XNNPACK) ; sinon sans délégué, et on le signale
    try:
        interp = tf.lite.Interpreter(model_path=chemin); interp.allocate_tensors(); return interp, True
    except RuntimeError as e:
        print("⚠️ XNNPACK refuse ce modèle :", str(e)[:120])
        interp = tf.lite.Interpreter(model_path=chemin,
            experimental_op_resolver_type=tf.lite.experimental.OpResolverType.BUILTIN_WITHOUT_DEFAULT_DELEGATES)
        interp.allocate_tensors(); return interp, False

XNNPACK_OK = {}
def eval_tflite(chemin):
    interp, xnnpack = interpreteur(chemin)
    XNNPACK_OK[chemin] = xnnpack
    print(os.path.basename(chemin), "| XNNPACK :", "oui" if xnnpack else "NON")
    ent, sor = interp.get_input_details()[0], interp.get_output_details()[0]
    assert tuple(sor["shape"]) == (1, len(CLASSES) + DIM), f"sortie inattendue {sor['shape']}"
    preds, embs, t = [], [], []
    for images, _ in test_ds.unbatch().batch(1):
        interp.set_tensor(ent["index"], tf.cast(images, tf.float32).numpy())
        t0 = time.perf_counter(); interp.invoke(); t.append(time.perf_counter() - t0)
        brut = interp.get_tensor(sor["index"])[0]
        preds.append(brut[:len(CLASSES)]); embs.append(brut[len(CLASSES):])
    preds = np.array(preds)
    # L'empreinte du .tflite doit donner la même décision de rejet que le modèle Keras
    s_tfl = ressemblance(np.array(embs))
    ecart = float(np.abs(s_tfl - s_test).max())
    meme_decision = float(((s_tfl >= SEUIL_OOD) == (s_test >= SEUIL_OOD)).mean())
    print(f"  empreinte : écart max {ecart:.4f} | même décision de rejet : {meme_decision:.1%}")
    return preds, float(np.median(t) * 1000), ecart, meme_decision

resultats = {}
for mode in MODES:
    chemin = f"{EXPORT}/{CULTURE}_classify_{VERSION}_{mode}.tflite"
    p, ms, ecart_emp, meme_rejet = eval_tflite(chemin)
    acc = float((p.argmax(1) == y_vrai).mean()); accord = float((p.argmax(1) == y_pred).mean())
    resultats[mode] = {"precision_test": acc, "accord_avec_keras": accord, "ms_cpu_colab": ms,
                       "taille_mo": os.path.getsize(chemin) / 1e6, "xnnpack": XNNPACK_OK[chemin],
                       "ecart_empreinte": ecart_emp, "meme_decision_rejet": meme_rejet}
    print(mode, resultats[mode])
    if mode == "fp16":   # le modèle principal DOIT être fidèle
        assert accord >= 0.97, f"fp16 : accord TFLite/Keras trop faible ({accord:.1%})"
        assert meme_rejet >= 0.97, f"fp16 : décision de rejet différente de Keras ({meme_rejet:.1%})"
    elif accord < 0.97 or meme_rejet < 0.97 or not XNNPACK_OK[chemin]:
        print(f"⚠️ {mode} écarté (accord {accord:.1%}) : on livre seulement le fp16")
        os.remove(chemin); resultats[mode]["ecarte"] = True
""")

md("## 7. Fiche modèle + archive à télécharger")
code("""
with open(f"{EXPORT}/labels_{CULTURE}.txt", "w") as f:
    f.write("\\n".join(CLASSES))
fiche = {
    "culture": CULTURE, "version": VERSION, "backbone": BACKBONE, "smoke": SMOKE,
    "entree": {"forme": [1, IMG, IMG, 3], "type": "float32", "plage": "RGB 0-255, sans normalisation (incluse dans le modèle)"},
    "sortie": f"vecteur [1, {len(CLASSES)} + {DIM}] : probas softmax (ordre labels_<culture>.txt) puis empreinte L2-normalisée",
    "rejet_ressemblance": OOD,
    "classes": CLASSES, "seuil_confiance": SEUIL, "seuil_certain": SEUIL_CERTAIN, "seuil_probable": SEUIL_PROBABLE,
    "test": {c: {k: round(rapport[c][k], 3) for k in ("precision", "recall", "f1-score", "support")} for c in CLASSES},
    "precision_globale": round(float(rapport["accuracy"]), 4),
    "go_no_go": GO, "tflite": resultats,
    "date": time.strftime("%Y-%m-%d"), "tensorflow": tf.__version__,
}
prototypes.astype("<f4").tofile(f"{EXPORT}/prototypes_{CULTURE}.bin")   # float32 little-endian, [N, DIM]
config_app = {"version": VERSION, "classes": CLASSES, "dim": DIM, "nb_prototypes": int(len(prototypes)),
              "seuil_certain": round(SEUIL_CERTAIN, 4), "seuil_probable": round(SEUIL_PROBABLE, 4),
              "seuil_ressemblance": round(SEUIL_OOD, 4)}
with open(f"{EXPORT}/config_{CULTURE}.json", "w") as f:
    json.dump(config_app, f, ensure_ascii=False, indent=2)
print("Config app :", config_app)
with open(f"{EXPORT}/fiche_modele.json", "w") as f:
    json.dump(fiche, f, ensure_ascii=False, indent=2)
shutil.make_archive(EXPORT, "zip", EXPORT)
print(json.dumps(fiche, ensure_ascii=False, indent=2))
if EN_COLAB:
    from google.colab import files
    files.download(EXPORT + ".zip")
else:
    print("Archive :", EXPORT + ".zip (onglet Output de Kaggle)")
""")

nb = {"cells": cellules, "metadata": {"accelerator": "GPU", "colab": {"gpuType": "T4", "provenance": []},
      "kernelspec": {"display_name": "Python 3", "name": "python3"}, "language_info": {"name": "python"}},
      "nbformat": 4, "nbformat_minor": 0}
sortie = RACINE / "notebooks" / "train_classify.ipynb"
sortie.write_text(json.dumps(nb, ensure_ascii=False, indent=1))
print("Écrit :", sortie)
