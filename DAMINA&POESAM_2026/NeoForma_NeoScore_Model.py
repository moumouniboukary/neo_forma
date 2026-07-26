"""
NeoForma — Modèle NeoScore Préliminaire
========================================
Auteur  : Équipe NeoForma (Mohamed [NOM], CEO)
Version : 1.0 — Burkina Faso, 2026
Licence : Confidentiel — Usage interne NeoForma uniquement

Description
-----------
Ce script implémente le pipeline complet d'analyse des données terrain :
  1. Génération de données synthétiques (simulation pré-collecte)
  2. Pré-traitement et encodage des variables
  3. Segmentation par clustering k-means (profils emprunteurs)
  4. Modèle NeoScore : régression logistique (variable cible = intérêt Likert ≥ 4)
  5. Scoring individuel sur 0–100
  6. Export des résultats (CSV) + visualisations (PNG)

Usage
-----
  python NeoForma_NeoScore_Model.py

Dépendances
-----------
  pip install pandas numpy scikit-learn matplotlib seaborn
"""

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import warnings
warnings.filterwarnings("ignore")

from sklearn.preprocessing import LabelEncoder, MinMaxScaler
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_score, StratifiedKFold
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA
from sklearn.metrics import classification_report, roc_auc_score

# ── Palette NeoForma ──────────────────────────────────────────────────────────
C_TEAL   = "#1D9E75"
C_TEAL_L = "#E1F5EE"
C_PURPLE = "#534AB7"
C_AMBER  = "#EF9F27"
C_CORAL  = "#D85A30"
C_GRAY   = "#888780"
PALETTE  = [C_TEAL, C_PURPLE, C_AMBER, C_CORAL]

np.random.seed(42)


# ═══════════════════════════════════════════════════════════════════════════════
# 1. GÉNÉRATION DE DONNÉES SYNTHÉTIQUES
#    → Remplacer par : df = pd.read_csv("neoforma_terrain_collecte.csv")
#      une fois la collecte terminée (export KoboCollect → CSV)
# ═══════════════════════════════════════════════════════════════════════════════

def generer_donnees_synthetiques(n=120):
    """
    Simule un jeu de données terrain représentatif des enquêtés NeoForma.
    Les distributions reflètent les hypothèses du business plan 2026.

    Paramètres
    ----------
    n : int — Nombre d'enquêtés (taille de l'échantillon cible)

    Retour
    ------
    pd.DataFrame — Jeu de données brut (format post-KoboCollect)
    """
    metiers = ["commerce", "mecanique", "artisanat", "menuiserie",
               "restauration", "transport", "agriculture", "services"]

    genres = np.random.choice(["homme", "femme"], n, p=[0.58, 0.42])
    ages   = np.random.choice(["m25","25_34","35_44","45_54","55p"], n,
                               p=[0.10, 0.35, 0.30, 0.18, 0.07])
    instrs = np.random.choice(["aucun","alpha","primaire","secondaire","superieur"], n,
                               p=[0.27, 0.18, 0.28, 0.20, 0.07])
    metier = np.random.choice(metiers, n,
                               p=[0.20, 0.17, 0.15, 0.13, 0.13, 0.10, 0.08, 0.04])
    ancien = np.random.choice(["m1","1_2","3_5","6_10","p10"], n,
                               p=[0.08, 0.15, 0.27, 0.28, 0.22])

    # CA journalier (FCFA) — représentation ordinale
    ca_map = {"m5k":1, "5_15k":2, "15_30k":3, "30_60k":4, "60_100k":5, "p100k":6}
    ca_labels = list(ca_map.keys())
    ca_jour = np.random.choice(ca_labels, n, p=[0.20, 0.32, 0.24, 0.14, 0.07, 0.03])

    nb_transactions = np.random.randint(2, 35, n)

    # Part crédit accordé aux clients
    part_credit = np.random.choice(["0_10","10_25","25_50","p50"], n,
                                    p=[0.35, 0.38, 0.20, 0.07])

    # Impayés (proxy risque)
    impayes_map = {"0":0, "m5k":1, "5_15k":2, "15_50k":3, "p50k":4}
    impayes = np.random.choice(list(impayes_map.keys()), n, p=[0.22, 0.35, 0.28, 0.12, 0.03])

    # Ancienneté → score ordinal
    ancien_map = {"m1":1, "1_2":2, "3_5":3, "6_10":4, "p10":5}

    # Tontine (signal fiabilité)
    tontine = np.random.choice(["oui","non"], n, p=[0.68, 0.32])
    tontine_cotis = np.where(tontine=="oui",
                             np.random.randint(2000, 25000, n), 0)
    tontine_ans   = np.where(tontine=="oui",
                             np.random.randint(1, 12, n), 0)

    # Compte bancaire
    compte = np.random.choice(["non","oui_actif","oui_dormant"], n, p=[0.72, 0.17, 0.11])

    # Historique crédit
    credit_hist = np.random.choice(["jamais","refuse","accorde"], n, p=[0.58, 0.30, 0.12])

    # Montant crédit souhaité
    besoin_credit = np.random.choice(["m50k","50_150k","150_500k","500k_2m","p2m"], n,
                                      p=[0.14, 0.28, 0.35, 0.18, 0.05])

    # Smartphone
    telephone = np.random.choice(["aucun","basique","smartphone","autre_smart"], n,
                                  p=[0.08, 0.35, 0.52, 0.05])

    # Mobile Money
    mobile_money = np.random.choice(["jamais","occasionnel","regulier","quotidien"], n,
                                     p=[0.18, 0.30, 0.33, 0.19])

    # VARIABLE DÉPENDANTE : intérêt NeoForma (Likert 1–5)
    # On introduit une corrélation réaliste avec les variables clés
    score_latent = (
        (pd.Series(ca_jour).map({"m5k":1,"5_15k":2,"15_30k":3,"30_60k":4,"60_100k":5,"p100k":6}) * 0.25)
        + (pd.Series(tontine).map({"oui":1.5,"non":0}))
        + (pd.Series(ancien).map(ancien_map) * 0.20)
        + (pd.Series(mobile_money).map({"jamais":0,"occasionnel":0.5,"regulier":1,"quotidien":2}))
        - (pd.Series(impayes).map(impayes_map) * 0.5)
        + np.random.normal(0, 0.8, n)
    )
    interet_raw = np.clip(np.round(score_latent / score_latent.max() * 4 + 1), 1, 5)
    interet = interet_raw.astype(int)

    # Langue préférée
    langue = np.random.choice(["francais","moore","dioula","fulfulde","icones"], n,
                               p=[0.28, 0.35, 0.22, 0.09, 0.06])

    # Consentement données
    consentement = np.random.choice(["oui_libre","oui_anonyme","oui_benefice","non"], n,
                                     p=[0.22, 0.35, 0.28, 0.15])

    df = pd.DataFrame({
        "id": [f"NEO{i:04d}" for i in range(1, n+1)],
        "genre": genres,
        "age": ages,
        "instruction": instrs,
        "metier": metier,
        "anciennete": ancien,
        "ca_jour": ca_jour,
        "nb_transactions": nb_transactions,
        "part_credit": part_credit,
        "impayes": impayes,
        "tontine": tontine,
        "tontine_cotis": tontine_cotis,
        "tontine_ans": tontine_ans,
        "compte": compte,
        "credit_hist": credit_hist,
        "besoin_credit": besoin_credit,
        "telephone": telephone,
        "mobile_money": mobile_money,
        "interet": interet,
        "langue": langue,
        "consentement": consentement,
    })
    return df


# ═══════════════════════════════════════════════════════════════════════════════
# 2. PRÉ-TRAITEMENT
# ═══════════════════════════════════════════════════════════════════════════════

def pretraiter(df):
    """
    Encode les variables catégorielles en valeurs numériques ordinales
    et normalise les variables continues sur [0, 1].

    Retour
    ------
    pd.DataFrame — Jeu de données prêt pour le modèle
    dict          — Mappings d'encodage pour interprétation ultérieure
    """
    df = df.copy()

    # ── Encodages ordinaux ──────────────────────────────────────────────────
    encodings = {
        "anciennete": {"m1":1, "1_2":2, "3_5":3, "6_10":4, "p10":5},
        "ca_jour":    {"m5k":1, "5_15k":2, "15_30k":3, "30_60k":4, "60_100k":5, "p100k":6},
        "part_credit":{"0_10":1, "10_25":2, "25_50":3, "p50":4},
        "impayes":    {"0":0, "m5k":1, "5_15k":2, "15_50k":3, "p50k":4},
        "mobile_money":{"jamais":0, "occasionnel":1, "regulier":2, "quotidien":3},
        "telephone":  {"aucun":0, "basique":1, "smartphone":2, "autre_smart":2},
        "compte":     {"non":0, "oui_dormant":1, "oui_actif":2},
        "credit_hist":{"jamais":0, "refuse":1, "accorde":2},
        "instruction":{"aucun":0, "alpha":1, "primaire":2, "secondaire":3, "superieur":4},
        "age":        {"m25":1, "25_34":2, "35_44":3, "45_54":4, "55p":5},
        "genre":      {"homme":0, "femme":1},
        "tontine":    {"non":0, "oui":1},
        "consentement":{"non":0, "oui_benefice":1, "oui_anonyme":2, "oui_libre":3},
    }

    for col, mapping in encodings.items():
        df[col + "_num"] = df[col].map(mapping)

    # ── Encodage one-hot pour le corps de métier ────────────────────────────
    df = pd.get_dummies(df, columns=["metier"], prefix="metier")

    # ── Normalisation des variables continues ───────────────────────────────
    scaler = MinMaxScaler()
    cols_num = ["tontine_cotis", "tontine_ans", "nb_transactions"]
    df[cols_num] = scaler.fit_transform(df[cols_num])

    return df, encodings


# ═══════════════════════════════════════════════════════════════════════════════
# 3. SEGMENTATION K-MEANS (Profils emprunteurs)
# ═══════════════════════════════════════════════════════════════════════════════

FEATURES_CLUSTERING = [
    "ca_jour_num", "nb_transactions", "impayes_num",
    "tontine_num", "tontine_cotis", "anciennete_num",
    "mobile_money_num", "telephone_num"
]

SEGMENT_LABELS = {
    0: ("Segment A", "Régulier stable",  C_TEAL),
    1: ("Segment B", "Potentiel volatil", C_PURPLE),
    2: ("Segment C", "Primo-entrant",    C_AMBER),
    3: ("Segment D", "Exclusion totale", C_CORAL),
}

def segmenter(df, k=4):
    """
    Applique k-means sur les variables de transaction pour identifier
    les profils emprunteurs distincts.
    """
    X = df[FEATURES_CLUSTERING].fillna(0)
    scaler = MinMaxScaler()
    X_scaled = scaler.fit_transform(X)

    km = KMeans(n_clusters=k, random_state=42, n_init=20)
    df["segment"] = km.fit_predict(X_scaled)

    # Réordonner les segments par CA médian croissant
    ca_moy = df.groupby("segment")["ca_jour_num"].mean().sort_values()
    remap = {old: new for new, old in enumerate(ca_moy.index)}
    df["segment"] = df["segment"].map(remap)

    return df, km, scaler


# ═══════════════════════════════════════════════════════════════════════════════
# 4. MODÈLE NEOSCORE — Régression logistique
# ═══════════════════════════════════════════════════════════════════════════════

# Variables prédictives et leurs poids théoriques (pour le scoring explicable)
NEOSCORE_WEIGHTS = {
    "ca_jour_num":       0.20,   # Volume CA journalier
    "impayes_num":      -0.20,   # Taux d'impayés (inversé)
    "anciennete_num":    0.15,   # Ancienneté de l'activité
    "tontine_num":       0.10,   # Participation tontine (proxy fiabilité)
    "tontine_cotis":     0.08,   # Montant cotisation tontine
    "tontine_ans":       0.07,   # Ancienneté dans la tontine
    "nb_transactions":   0.10,   # Nombre de transactions / jour
    "mobile_money_num":  0.05,   # Adoption Mobile Money
    "telephone_num":     0.03,   # Type de téléphone
    "consentement_num":  0.02,   # Consentement partage données
}

FEATURES_SCORING = list(NEOSCORE_WEIGHTS.keys())


def calculer_neoscore(df):
    """
    Calcule le NeoScore sur 0–100 pour chaque enquêté.

    Méthode : combinaison linéaire pondérée des variables normalisées,
    puis transformation en score 0–100.
    Les poids négatifs (impayés) réduisent le score.

    Retour
    ------
    pd.Series — NeoScore (0–100) pour chaque enquêté
    """
    score_brut = sum(
        df[feat].fillna(0) * weight
        for feat, weight in NEOSCORE_WEIGHTS.items()
    )
    # Normalisation sur [0, 100]
    s_min, s_max = score_brut.min(), score_brut.max()
    neoscore = ((score_brut - s_min) / (s_max - s_min) * 100).round(1)
    return neoscore


def entrainer_modele(df):
    """
    Entraîne un modèle de régression logistique pour prédire si un enquêté
    est intéressé par NeoForma (intérêt Likert ≥ 4).

    Évaluation : cross-validation 5 folds stratifiée + AUC ROC.

    Retour
    ------
    LogisticRegression — Modèle entraîné
    float              — AUC ROC moyen (cross-validation)
    dict               — Coefficients du modèle par variable
    """
    X = df[FEATURES_SCORING].fillna(0)
    y = (df["interet"] >= 4).astype(int)

    scaler = MinMaxScaler()
    X_scaled = scaler.fit_transform(X)

    clf = LogisticRegression(max_iter=1000, random_state=42, C=1.0)

    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    scores_auc = cross_val_score(clf, X_scaled, y, cv=cv, scoring="roc_auc")

    clf.fit(X_scaled, y)

    coefficients = dict(zip(FEATURES_SCORING, clf.coef_[0]))

    return clf, scores_auc.mean(), coefficients


# ═══════════════════════════════════════════════════════════════════════════════
# 5. VISUALISATIONS
# ═══════════════════════════════════════════════════════════════════════════════

def visualiser(df):
    """
    Génère 4 graphiques d'analyse et les sauvegarde en PNG.
    """
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    fig.patch.set_facecolor("white")
    fig.suptitle("NeoForma — Analyse Terrain 2026", fontsize=16,
                 fontweight="bold", color=C_TEAL, y=1.01)

    # ── 1. Distribution du NeoScore par segment ────────────────────────────
    ax = axes[0, 0]
    for seg_id, (seg_code, seg_name, seg_color) in SEGMENT_LABELS.items():
        subset = df[df["segment"] == seg_id]["neoscore"]
        if not subset.empty:
            ax.hist(subset, bins=15, alpha=0.7, color=seg_color,
                    label=f"{seg_code} — {seg_name} (n={len(subset)})")
    ax.axvline(x=50, color=C_GRAY, linestyle="--", linewidth=1, label="Seuil 50")
    ax.set_title("Distribution du NeoScore par segment", fontweight="bold", color=C_TEAL)
    ax.set_xlabel("NeoScore (0–100)")
    ax.set_ylabel("Nombre d'enquêtés")
    ax.legend(fontsize=8)
    ax.set_facecolor("#FAFAFA")
    ax.spines[["top","right"]].set_visible(False)

    # ── 2. NeoScore médian par corps de métier ────────────────────────────
    ax = axes[0, 1]
    metier_cols = [c for c in df.columns if c.startswith("metier_")]
    metier_scores = {}
    for mc in metier_cols:
        m_name = mc.replace("metier_", "").capitalize()
        scores = df[df[mc] == 1]["neoscore"]
        if not scores.empty:
            metier_scores[m_name] = scores.median()
    ms_series = pd.Series(metier_scores).sort_values()
    colors_bar = [C_TEAL if v >= 50 else C_AMBER for v in ms_series.values]
    bars = ax.barh(ms_series.index, ms_series.values, color=colors_bar, edgecolor="white")
    ax.axvline(x=50, color=C_GRAY, linestyle="--", linewidth=1)
    for bar, val in zip(bars, ms_series.values):
        ax.text(val + 0.5, bar.get_y() + bar.get_height()/2,
                f"{val:.0f}", va="center", fontsize=8, color=C_TEAL)
    ax.set_title("NeoScore médian par corps de métier", fontweight="bold", color=C_TEAL)
    ax.set_xlabel("NeoScore médian")
    ax.set_facecolor("#FAFAFA")
    ax.spines[["top","right"]].set_visible(False)

    # ── 3. Clustering PCA 2D ──────────────────────────────────────────────
    ax = axes[1, 0]
    X_pca_raw = df[FEATURES_CLUSTERING].fillna(0)
    pca = PCA(n_components=2, random_state=42)
    coords = pca.fit_transform(MinMaxScaler().fit_transform(X_pca_raw))
    for seg_id, (seg_code, seg_name, seg_color) in SEGMENT_LABELS.items():
        mask = df["segment"] == seg_id
        ax.scatter(coords[mask, 0], coords[mask, 1],
                   c=seg_color, alpha=0.65, s=40, label=f"{seg_code}",
                   edgecolors="white", linewidths=0.4)
    ax.set_title("Segmentation PCA (vue 2D)", fontweight="bold", color=C_TEAL)
    ax.set_xlabel(f"Composante 1 ({pca.explained_variance_ratio_[0]*100:.1f}%)")
    ax.set_ylabel(f"Composante 2 ({pca.explained_variance_ratio_[1]*100:.1f}%)")
    ax.legend(fontsize=8)
    ax.set_facecolor("#FAFAFA")
    ax.spines[["top","right"]].set_visible(False)

    # ── 4. Intérêt NeoForma par genre et tontine ─────────────────────────
    ax = axes[1, 1]
    groups = {
        "Femme + Tontine":  df[(df["genre"]=="femme") & (df["tontine"]=="oui")]["interet"],
        "Femme sans Tontine": df[(df["genre"]=="femme") & (df["tontine"]=="non")]["interet"],
        "Homme + Tontine":  df[(df["genre"]=="homme") & (df["tontine"]=="oui")]["interet"],
        "Homme sans Tontine": df[(df["genre"]=="homme") & (df["tontine"]=="non")]["interet"],
    }
    group_colors = [C_TEAL, C_TEAL_L, C_PURPLE, "#AFA9EC"]
    positions = range(1, len(groups)+1)
    bp = ax.boxplot([g.values for g in groups.values()], positions=positions,
                    patch_artist=True, widths=0.6,
                    medianprops=dict(color="white", linewidth=2))
    for patch, color in zip(bp["boxes"], group_colors):
        patch.set_facecolor(color)
    ax.set_xticks(positions)
    ax.set_xticklabels(groups.keys(), rotation=20, ha="right", fontsize=8)
    ax.set_title("Intérêt NeoForma par profil", fontweight="bold", color=C_TEAL)
    ax.set_ylabel("Score Likert (1–5)")
    ax.axhline(y=4, color=C_AMBER, linestyle="--", linewidth=1, label="Seuil intérêt ≥ 4")
    ax.legend(fontsize=8)
    ax.set_facecolor("#FAFAFA")
    ax.spines[["top","right"]].set_visible(False)

    plt.tight_layout()
    path_fig = "/home/claude/NeoForma_NeoScore_Visualisations.png"
    plt.savefig(path_fig, dpi=150, bbox_inches="tight", facecolor="white")
    plt.close()
    print(f"  Visualisations sauvegardées : {path_fig}")
    return path_fig


# ═══════════════════════════════════════════════════════════════════════════════
# 6. RAPPORT TERMINAL + EXPORTS
# ═══════════════════════════════════════════════════════════════════════════════

def afficher_rapport(df, auc, coefficients):
    """Affiche un rapport de synthèse dans le terminal."""
    sep = "─" * 70
    print(f"\n{'═'*70}")
    print(f"  NeoForma — NeoScore · Rapport d'Analyse")
    print(f"{'═'*70}")

    print(f"\n{sep}")
    print(f"  ÉCHANTILLON : {len(df)} enquêtés")
    print(f"{sep}")
    print(f"  Genre        : H {(df['genre']=='homme').mean()*100:.1f}% · F {(df['genre']=='femme').mean()*100:.1f}%")
    print(f"  Tontine      : {(df['tontine']=='oui').mean()*100:.1f}% de participants")
    print(f"  Bancarisation: {(df['compte']=='oui_actif').mean()*100:.1f}% de comptes actifs")
    print(f"  Smartphone   : {(df['telephone']=='smartphone').mean()*100:.1f}% possèdent un smartphone")

    print(f"\n{sep}")
    print(f"  NEOSCORE — Statistiques descriptives")
    print(f"{sep}")
    print(f"  Médiane       : {df['neoscore'].median():.1f} / 100")
    print(f"  Moyenne       : {df['neoscore'].mean():.1f} / 100")
    print(f"  Éligibles ≥ 50: {(df['neoscore'] >= 50).mean()*100:.1f}% de l'échantillon")
    print(f"  Éligibles ≥ 65: {(df['neoscore'] >= 65).mean()*100:.1f}% de l'échantillon")

    print(f"\n{sep}")
    print(f"  SEGMENTATION — Répartition des profils")
    print(f"{sep}")
    for seg_id, (code, name, _) in SEGMENT_LABELS.items():
        n_seg = (df["segment"] == seg_id).sum()
        med_score = df[df["segment"] == seg_id]["neoscore"].median()
        print(f"  {code} · {name:<22}: {n_seg:3d} enquêtés "
              f"({n_seg/len(df)*100:.1f}%) · NeoScore médian {med_score:.0f}")

    print(f"\n{sep}")
    print(f"  MODÈLE DE CLASSIFICATION — Performance")
    print(f"{sep}")
    print(f"  Variable cible : Intérêt NeoForma ≥ 4 (Likert)")
    print(f"  Taux positifs  : {(df['interet']>=4).mean()*100:.1f}% de l'échantillon")
    print(f"  AUC ROC (CV-5) : {auc:.3f}  {'✓ Bon' if auc >= 0.70 else '⚠ À améliorer'}")

    print(f"\n{sep}")
    print(f"  COEFFICIENTS DU MODÈLE (top variables)")
    print(f"{sep}")
    coef_sorted = sorted(coefficients.items(), key=lambda x: abs(x[1]), reverse=True)
    for feat, coef in coef_sorted[:8]:
        direction = "↑" if coef > 0 else "↓"
        print(f"  {direction} {feat:<30}: {coef:+.3f}")

    print(f"\n{sep}")
    print(f"  ADOPTION NUMÉRIQUE")
    print(f"{sep}")
    lang_dist = df["langue"].value_counts(normalize=True) * 100
    for lang, pct in lang_dist.items():
        print(f"  Langue préférée · {lang:<12}: {pct:.1f}%")
    consent_dist = df["consentement"].value_counts(normalize=True) * 100
    print()
    for con, pct in consent_dist.items():
        print(f"  Consentement   · {con:<20}: {pct:.1f}%")

    print(f"\n{'═'*70}")
    print(f"  Double exclusion : {((df['telephone']=='aucun') | (df['telephone']=='basique')).mean()*100:.1f}% sans smartphone")
    print(f"                     {(df['instruction_num']<=1).mean()*100:.1f}% avec niveau d'instruction ≤ alphabétisation")
    print(f"  → Segment cible roadmap accessibilité vocale Masakhane")
    print(f"{'═'*70}\n")


# ═══════════════════════════════════════════════════════════════════════════════
# PIPELINE PRINCIPAL
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("\n┌─────────────────────────────────────────────────────────────┐")
    print("│  NeoForma · NeoScore Model Pipeline v1.0                    │")
    print("│  Burkina Faso — Étude de Terrain 2026                       │")
    print("└─────────────────────────────────────────────────────────────┘")

    # ── Étape 1 : Données ──────────────────────────────────────────────────
    print("\n[1/6] Chargement des données...")
    # ⚠ Remplacer par : df_raw = pd.read_csv("neoforma_terrain_collecte.csv")
    df_raw = generer_donnees_synthetiques(n=120)
    print(f"      → {len(df_raw)} enquêtés chargés (données synthétiques).")
    df_raw.to_csv("/home/claude/neoforma_terrain_simule.csv", index=False)
    print("      → Export CSV : neoforma_terrain_simule.csv")

    # ── Étape 2 : Pré-traitement ───────────────────────────────────────────
    print("\n[2/6] Pré-traitement et encodage...")
    df, encodings = pretraiter(df_raw)
    print(f"      → {len(df.columns)} variables après encodage.")

    # ── Étape 3 : Segmentation ─────────────────────────────────────────────
    print("\n[3/6] Segmentation k-means (k=4)...")
    df, km_model, km_scaler = segmenter(df, k=4)
    for seg_id, (code, name, _) in SEGMENT_LABELS.items():
        n = (df["segment"] == seg_id).sum()
        print(f"      → {code} · {name}: {n} enquêtés ({n/len(df)*100:.1f}%)")

    # ── Étape 4 : NeoScore ────────────────────────────────────────────────
    print("\n[4/6] Calcul du NeoScore (0–100)...")
    df["neoscore"] = calculer_neoscore(df)
    print(f"      → Médiane : {df['neoscore'].median():.1f} · Éligibles ≥50 : {(df['neoscore']>=50).mean()*100:.1f}%")

    # ── Étape 5 : Modèle de classification ───────────────────────────────
    print("\n[5/6] Entraînement modèle de classification (régression logistique)...")
    clf, auc, coefficients = entrainer_modele(df)
    print(f"      → AUC ROC (CV-5) : {auc:.3f}")

    # ── Étape 6 : Visualisations + Exports ───────────────────────────────
    print("\n[6/6] Génération des visualisations et exports...")
    visualiser(df)
    df_export = df_raw.copy()
    df_export["neoscore"] = df["neoscore"].values
    df_export["segment"] = df["segment"].map(
        {k: f"{v[0]} - {v[1]}" for k, v in SEGMENT_LABELS.items()})
    df_export["eligible_credit"] = (df["neoscore"] >= 50).map({True: "Oui", False: "Non"})
    df_export.to_csv("/home/claude/neoforma_resultats_scores.csv", index=False)
    print("      → Export CSV : neoforma_resultats_scores.csv")

    # ── Rapport final ──────────────────────────────────────────────────────
    afficher_rapport(df, auc, coefficients)

    print("Pipeline terminé. Fichiers générés :")
    print("  · neoforma_terrain_simule.csv")
    print("  · neoforma_resultats_scores.csv")
    print("  · NeoForma_NeoScore_Visualisations.png")
    print("\n⚠  Pour utiliser avec les vraies données terrain :")
    print("   Remplacer generer_donnees_synthetiques() par :")
    print("   df_raw = pd.read_csv('neoforma_terrain_collecte.csv')")
