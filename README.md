# Dengue_CHUR
Analyse des facteurs associés à la dengue au CHUR de Ouahigouya et prévisions T3-T4 2026




# Analyse de la Dengue au CHUR de Ouahigouya

## Contexte
Projet d'analyse des facteurs associés à la dengue confirmée et prévision de l'évolution des cas suspects au 3e et 4e trimestre 2026 au CHUR de Ouahigouya (Burkina Faso).

## Données
- **Période** : Janvier 2024 - Juin 2026
- **Effectif** : 8 777 cas suspects
- **Variables** : Âge, sexe, symptômes, tests biologiques, confirmation dengue

## Méthodes
- Régression logistique (univariée, multivariée, stratifiée)
- Modèle SARIMA (prévisions)

## Principaux résultats
- **Facteur associé** : Diarrhées (OR = 0,63 ; IC 95% : 0,39-1,00 ; p = 0,048)
- **Effet modificateur** : Paludisme
- **Prévisions T3 2026** : 387 cas suspects (IC 95%)
- **Prévisions T4 2026** : 434 cas suspects (IC 95%)

## Structure du dépôt
- `Analyse_Dengue_CHUR_Ouahigouya_FINAL.do` : Code Stata complet
- `Base_Dengue_Nettoyee.dta` : Base de données nettoyée
- `Graphiques/` : Tous les graphiques générés
- `Tableaux/` : Tous les tableaux exportés
- `Previsions/` : Fichiers de prévisions

## Auteur
Oualilaye Sawadogo

## Licence
MIT
