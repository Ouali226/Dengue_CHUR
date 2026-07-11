/*==========================================================================
 PROJET   : Facteurs associes a la manifestation de la dengue au CHUR de
            Ouahigouya et prediction de l'evolution au 3e et 4e trimestre 2026
 Auteur   : Oualilaye Sawadogo
 Logiciel : Stata 16
 Fichier  : Analyse_Dengue_CHUR_Ouahigouya_FINAL.do

 CORRECTION APPORTEE DANS CETTE VERSION (par rapport a Analyse_super.do) :
 Juillet 2026 ne comptait que 5 cas suspects dans la base, parce que le mois
 venait tout juste de commencer au moment de l'extraction (quelques semaines
 seulement sur les ~4-5 que compte le mois). Ce chiffre n'est donc PAS un
 mois complet observe : il sous-estime tres fortement le vrai volume du
 mois. Le laisser dans la serie comme s'il etait complet faussait a la fois
 l'estimation du modele SARIMA (un "creux" artificiel juste avant la
 prevision) et le tableau des previsions (juillet apparaissait "observe"
 avec seulement 5 cas au lieu d'etre prevu comme le reste du 3e trimestre).
 Correction : juillet 2026 est maintenant traite comme une periode MANQUANTE
 (donc exclue de l'estimation du modele, comme n'importe quel mois futur),
 et il est desormais PREVU au meme titre qu'aout a decembre 2026. L'horizon
 de prevision passe ainsi de 5 a 6 mois (juillet a decembre 2026), et le
 dernier mois reellement observe et utilise pour estimer le modele devient
 juin 2026.
==========================================================================*/

clear all
set more off
capture log close
set linesize 255
version 16

*----------------------------------------------------------------------
* SECTION 0 : PARAMETRES A MODIFIER
*----------------------------------------------------------------------
global DOSSIER   "C:\Users\ouali\Downloads\AU_CHAUD\Projet_Dengue4"
global FICHIER   "$DOSSIER\Base_Pret.xlsx"
global FEUILLE   "Base_fusionnee"

capture mkdir "$DOSSIER"
capture mkdir "$DOSSIER\Graphiques"
capture mkdir "$DOSSIER\Tableaux"
capture mkdir "$DOSSIER\Previsions"

cd "$DOSSIER"
capture log using "$DOSSIER\log_analyse_dengue_final.log", replace text

display "======================================================="
display " ANALYSE DE LA DENGUE - CHUR DE OUAHIGOUYA"
display " FACTEURS ASSOCIES ET PREVISIONS T3-T4 2026"
display " VERSION FINALE - JUILLET 2026 EXCLU DE L'OBSERVE ET PREVU"
display "======================================================="

*----------------------------------------------------------------------
* SECTION 1 : IMPORTATION DE Base_Pret
*----------------------------------------------------------------------
import excel "C:\Users\ouali\Downloads\AU_CHAUD\Base_Pret", sheet("Base_fusionnee") firstrow clear case(lower)
compress
save "$DOSSIER\Base_Pret_Brute.dta", replace

describe
count
display "Importation terminee. N = " _N

*----------------------------------------------------------------------
* SECTION 2 : AUDIT INITIAL
*----------------------------------------------------------------------
misstable summarize
codebook annee semaine_epi, compact

summ age, detail
summ pouls, detail
summ tension_arterielle, detail

display "Valeurs de semaine_epi hors intervalle [1,52] :"
list annee semaine_epi if (semaine_epi < 1 | semaine_epi > 52) & !missing(semaine_epi)

*----------------------------------------------------------------------
* SECTION 3 : RECODAGE DES VARIABLES
*----------------------------------------------------------------------

* -- 3.1 Variables binaires Oui/Non ------------------------------------
foreach v of varlist fievre_aigue cephalees myalgies nausees_vomissements ///
    diarrhees leucopenie test_paludisme {
    capture drop `v'_bin
    gen byte `v'_bin = 1 if `v' == "Oui"
    replace `v'_bin = 0 if `v' == "Non"
}

label variable fievre_aigue_bin              "Fievre aigue < 7 jours"
label variable cephalees_bin                 "Cephalees / douleur retro-orbitaire"
label variable myalgies_bin                  "Myalgies / arthralgies"
label variable nausees_vomissements_bin      "Nausees / vomissements"
label variable diarrhees_bin                 "Diarrhees"
label variable leucopenie_bin                "Leucopenie"
label variable test_paludisme_bin            "Test du paludisme positif"

* -- 3.2 Sexe -----------------------------------------------------------
capture drop sexe_num
gen byte sexe_num = 1 if sexe == "M"
replace sexe_num = 0 if sexe == "F"
label define sexe_lbl 0 "Feminin" 1 "Masculin", replace
label values sexe_num sexe_lbl
label variable sexe_num "Sexe"

* -- 3.3 Tests biologiques -----------------------------------------------
foreach v in ns1 igm igg {
    capture drop `v'_pos
    gen byte `v'_pos = 1 if `v' == "Positif"
    replace `v'_pos = 0 if `v' == "Negatif" | `v' == "Négatif"
    label variable `v'_pos "`v' positif"
}

* -- 3.4 Variable dependante : confirmation biologique de la dengue ------
capture drop dengue
gen byte dengue = 1 if confirmation_dengue == "Positif"
replace dengue  = 0 if confirmation_dengue == "Négatif" | confirmation_dengue == "Negatif"
label define dengue_lbl 0 "Non confirme" 1 "Confirme (NS1/IgM/IgG+)", replace
label values dengue dengue_lbl
label variable dengue "Confirmation biologique de la dengue"

tab dengue, missing

* -- 3.5 Tranches d'age ---------------------------------------------------
capture drop tranche_age
gen byte tranche_age = .
replace tranche_age = 1 if age <  15
replace tranche_age = 2 if age >= 15 & age < 25
replace tranche_age = 3 if age >= 25 & age < 45
replace tranche_age = 4 if age >= 45 & age < 60
replace tranche_age = 5 if age >= 60 & !missing(age)

label define age_lbl 1 "<15 ans" 2 "15-24 ans" 3 "25-44 ans" ///
    4 "45-59 ans" 5 "60 ans et plus", replace
label values tranche_age age_lbl
label variable tranche_age "Tranche d'age"

* -- 3.6 Date calendaire reconstruite -------------------------------------
capture drop date_cas mois_cal annee_cal mtemp
gen date_cas = mdy(1,1,annee) + (semaine_epi - 1) * 7 if !missing(annee, semaine_epi)
format date_cas %td
gen mois_cal  = month(date_cas)
gen annee_cal = year(date_cas)
gen mtemp = ym(annee_cal, mois_cal)
format mtemp %tm
label variable mtemp "Mois calendaire (annee-mois)"

display "Recodage termine."

*----------------------------------------------------------------------
* SECTION 4 : SAUVEGARDE DE LA BASE NETTOYEE
*----------------------------------------------------------------------
save "$DOSSIER\Base_Dengue_Nettoyee.dta", replace
display "Base nettoyee sauvegardee : Base_Dengue_Nettoyee.dta"

*----------------------------------------------------------------------
* SECTION 5 : STATISTIQUES DESCRIPTIVES
*----------------------------------------------------------------------
set scheme s2color

display "=== Variables quantitatives ==="
tabstat age pouls tension_arterielle, ///
    statistics(n mean sd median p25 p75 min max) columns(statistics)

* --- Tableau 1 : statistiques descriptives (quantitatives) --------------
preserve
    local i = 1
    foreach v in age pouls tension_arterielle {
        qui summ `v'
        matrix row_`i' = (r(N), r(mean), r(sd), r(min), r(max))
        local i = `i' + 1
    }
    clear
    set obs 3
    gen Variable = ""
    gen N = .
    gen Moyenne = .
    gen Ecart_type = .
    gen Minimum = .
    gen Maximum = .
    local noms `""Age (annees)" "Pouls (bpm)" "Tension arterielle""'
    forvalues i = 1/3 {
        local nom : word `i' of `noms'
        replace Variable   = "`nom'" in `i'
        replace N          = row_`i'[1,1] in `i'
        replace Moyenne    = row_`i'[1,2] in `i'
        replace Ecart_type = row_`i'[1,3] in `i'
        replace Minimum    = row_`i'[1,4] in `i'
        replace Maximum    = row_`i'[1,5] in `i'
    }
    export excel using "$DOSSIER\Tableaux\Tableau1_Statistiques_Descriptives.xlsx", firstrow(variables) replace
restore
display "Tableau 1 exporte."

* --- Tableau 2 : caracteristiques generales -------------------------------
preserve
    qui count if !missing(sexe_num)
    local N_sexe = r(N)
    local N_total = _N

    qui count if sexe_num == 0
    local e1 = r(N)
    qui count if sexe_num == 1
    local e2 = r(N)
    qui count if tranche_age == 1
    local e3 = r(N)
    qui count if tranche_age == 2
    local e4 = r(N)
    qui count if tranche_age == 3
    local e5 = r(N)
    qui count if tranche_age == 4
    local e6 = r(N)
    qui count if tranche_age == 5
    local e7 = r(N)
    qui count if dengue == 1
    local e8 = r(N)
    qui count if dengue == 0
    local e9 = r(N)

    clear
    set obs 9
    gen Variable = ""
    gen Effectif = .
    gen Pourcentage = ""

    replace Variable = "Sexe feminin"            in 1
    replace Variable = "Sexe masculin"           in 2
    replace Variable = "Tranche <15 ans"         in 3
    replace Variable = "Tranche 15-24 ans"       in 4
    replace Variable = "Tranche 25-44 ans"       in 5
    replace Variable = "Tranche 45-59 ans"       in 6
    replace Variable = "Tranche >=60 ans"        in 7
    replace Variable = "Cas confirmes (bio.)"    in 8
    replace Variable = "Cas non confirmes"       in 9

    replace Effectif = `e1' in 1
    replace Effectif = `e2' in 2
    replace Effectif = `e3' in 3
    replace Effectif = `e4' in 4
    replace Effectif = `e5' in 5
    replace Effectif = `e6' in 6
    replace Effectif = `e7' in 7
    replace Effectif = `e8' in 8
    replace Effectif = `e9' in 9

    replace Pourcentage = string(`e1'/`N_sexe'*100,  "%4.2f") + "% (sexe renseigne)" in 1
    replace Pourcentage = string(`e2'/`N_sexe'*100,  "%4.2f") + "% (sexe renseigne)" in 2
    replace Pourcentage = string(`e3'/`N_total'*100, "%4.2f") + "%" in 3
    replace Pourcentage = string(`e4'/`N_total'*100, "%4.2f") + "%" in 4
    replace Pourcentage = string(`e5'/`N_total'*100, "%4.2f") + "%" in 5
    replace Pourcentage = string(`e6'/`N_total'*100, "%4.2f") + "%" in 6
    replace Pourcentage = string(`e7'/`N_total'*100, "%4.2f") + "%" in 7
    replace Pourcentage = string(`e8'/`N_total'*100, "%4.2f") + "%" in 8
    replace Pourcentage = string(`e9'/`N_total'*100, "%4.2f") + "%" in 9

    export excel using "$DOSSIER\Tableaux\Tableau2_Caracteristiques.xlsx", firstrow(variables) replace
restore
display "Tableau 2 exporte (N total = " _N ")."

*----------------------------------------------------------------------
* SECTION 6 : GRAPHIQUES DESCRIPTIFS
*----------------------------------------------------------------------
histogram age, frequency normal ///
    title("Distribution de l'age des patients", size(medium)) ///
    subtitle("CHUR de Ouahigouya, 2024-2026 (n=`=_N')", size(small)) ///
    xtitle("Age (annees)", size(small)) ytitle("Effectif", size(small)) ///
    color(navy%70) ///
    graphregion(color(white)) plotregion(color(white)) ///
    ylabel(, angle(horizontal) glcolor(gs14) glwidth(vthin)) ///
    name(hist_age, replace)
graph export "$DOSSIER\Graphiques\Histogramme_Age.png", replace width(2000) height(1300)

graph bar (count), over(sexe_num, label(labsize(small))) ///
    title("Repartition des patients selon le sexe", size(medium)) ///
    ytitle("Effectif", size(small)) ///
    bar(1, color(navy%80)) ///
    blabel(bar, size(small)) ///
    graphregion(color(white)) plotregion(color(white)) ///
    ylabel(, angle(horizontal)) ///
    name(bar_sexe, replace)
graph export "$DOSSIER\Graphiques\Bar_Sexe.png", replace width(2000) height(1300)

graph bar (count), over(dengue, label(labsize(small))) ///
    title("Repartition des cas selon la confirmation biologique", size(medium)) ///
    ytitle("Effectif", size(small)) ///
    bar(1, color(maroon%80)) ///
    blabel(bar, size(small)) ///
    graphregion(color(white)) plotregion(color(white)) ///
    ylabel(, angle(horizontal)) ///
    name(bar_dengue, replace)
graph export "$DOSSIER\Graphiques\Bar_Dengue.png", replace width(2000) height(1300)

graph bar (mean) fievre_aigue_bin cephalees_bin myalgies_bin ///
    nausees_vomissements_bin diarrhees_bin, ///
    title("Prevalence des symptomes rapportes", size(medium)) ///
    ytitle("Proportion", size(small)) ///
    legend(order(1 "Fievre" 2 "Cephalees" 3 "Myalgies" 4 "Nausees/vomiss." 5 "Diarrhees") ///
        size(small) position(6) rows(2)) ///
    bar(1, color(navy%80)) bar(2, color(maroon%80)) bar(3, color(forest_green%80)) ///
    bar(4, color(orange%80)) bar(5, color(purple%80)) ///
    graphregion(color(white)) plotregion(color(white)) ///
    ylabel(, angle(horizontal)) ///
    name(bar_symptomes, replace)
graph export "$DOSSIER\Graphiques\Bar_Symptomes.png", replace width(2000) height(1300)

graph bar (count), over(tranche_age, label(labsize(vsmall) angle(30))) ///
    title("Repartition des patients par tranche d'age", size(medium)) ///
    ytitle("Effectif", size(small)) ///
    bar(1, color(teal%80)) ///
    blabel(bar, size(small)) ///
    graphregion(color(white)) plotregion(color(white)) ///
    ylabel(, angle(horizontal)) ///
    name(bar_age, replace)
graph export "$DOSSIER\Graphiques\Bar_TrancheAge.png", replace width(2000) height(1300)

display "Graphiques descriptifs generes."

*----------------------------------------------------------------------
* SECTION 7 : ANALYSE BIVARIEE
*----------------------------------------------------------------------
display "=== ANALYSE BIVARIEE : variables qualitatives ==="
tab sexe_num dengue, row chi2
tab tranche_age dengue, row chi2
tab fievre_aigue_bin dengue, row chi2
tab cephalees_bin dengue, row chi2
tab myalgies_bin dengue, row chi2
tab nausees_vomissements_bin dengue, row chi2
tab diarrhees_bin dengue, row chi2
tab test_paludisme_bin dengue, row chi2

display "=== ANALYSE BIVARIEE : variables quantitatives ==="
ttest age, by(dengue)
ttest pouls, by(dengue)

graph box age, over(dengue) ///
    title("Age selon le statut de confirmation biologique", size(medium)) ///
    ytitle("Age (annees)", size(small)) ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(box_age, replace)
graph export "$DOSSIER\Graphiques\Boxplot_Age_Dengue.png", replace width(2000) height(1300)

graph box pouls, over(dengue) ///
    title("Pouls selon le statut de confirmation biologique", size(medium)) ///
    ytitle("Pouls (bpm)", size(small)) ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(box_pouls, replace)
graph export "$DOSSIER\Graphiques\Boxplot_Pouls_Dengue.png", replace width(2000) height(1300)

local vars fievre_aigue_bin cephalees_bin myalgies_bin nausees_vomissements_bin diarrhees_bin test_paludisme_bin sexe_num tranche_age
local noms `""Fievre" "Cephalees" "Myalgies" "Nausees/vomissements" "Diarrhees" "Test paludisme" "Sexe" "Tranche d'age""'

local i = 1
foreach v of local vars {
    qui tab `v' dengue, chi2
    matrix res_`i' = (r(chi2), r(p))
    local i = `i' + 1
}

preserve
    clear
    set obs 8
    gen Variable = ""
    gen Chi2 = .
    gen P_value = .
    forvalues i = 1/8 {
        local nom : word `i' of `noms'
        replace Variable = "`nom'" in `i'
        replace Chi2 = res_`i'[1,1] in `i'
        replace P_value = res_`i'[1,2] in `i'
    }
    export excel using "$DOSSIER\Tableaux\Tableau3_Analyse_Bivariee.xlsx", firstrow(variables) replace
restore
display "Tableau 3 exporte."

*----------------------------------------------------------------------
* SECTION 8 : REGRESSIONS LOGISTIQUES UNIVARIEES
*----------------------------------------------------------------------
display "=== REGRESSIONS UNIVARIEES ==="
logistic dengue age, or
logistic dengue sexe_num, or
logistic dengue fievre_aigue_bin, or
logistic dengue cephalees_bin, or
logistic dengue myalgies_bin, or
logistic dengue nausees_vomissements_bin, or
logistic dengue diarrhees_bin, or
logistic dengue test_paludisme_bin, or
logistic dengue pouls, or
logistic dengue tension_arterielle, or

*----------------------------------------------------------------------*----------------------------------------------------------------------
*----------------------------------------------------------------------
* SECTION 9 : REGRESSION LOGISTIQUE MULTIVARIEE - MODELE SANS PALUDISME
*----------------------------------------------------------------------
display "======================================================="
display " MODELE LOGISTIQUE MULTIVARIE SANS PALUDISME"
display "======================================================="

count if !missing(dengue, age, sexe_num, fievre_aigue_bin, cephalees_bin, ///
    myalgies_bin, nausees_vomissements_bin, diarrhees_bin)
local N_reg = r(N)
display "Observations utilisees : `N_reg'"

logistic dengue age sexe_num fievre_aigue_bin cephalees_bin myalgies_bin ///
    nausees_vomissements_bin diarrhees_bin, or

estat classification
estat gof, group(10)
lroc
graph export "$DOSSIER\Graphiques\ROC_Logistique_Sans_Paludisme.png", replace width(2000) height(1300)

*--- Export du tableau des résultats ---
matrix b = e(b)
matrix V = e(V)
local nvars : colnames b
local k : word count `nvars'

preserve
    clear
    set obs `k'
    gen Variable = ""
    gen OR = .
    gen IC_inf95 = .
    gen IC_sup95 = .
    gen P_value = .

    forvalues i = 1/`k' {
        local nom : word `i' of `nvars'
        local coef = b[1,`i']
        local se   = sqrt(V[`i',`i'])
        local or_  = exp(`coef')
        local li   = exp(`coef' - 1.96*`se')
        local ls   = exp(`coef' + 1.96*`se')
        local p    = 2*(1 - normal(abs(`coef'/`se')))

        replace Variable  = "`nom'" in `i'
        replace OR        = `or_' in `i'
        replace IC_inf95  = `li' in `i'
        replace IC_sup95  = `ls' in `i'
        replace P_value   = `p' in `i'
    }
    export excel using "$DOSSIER\Tableaux\Tableau4_Regression_Logistique_Sans_Paludisme.xlsx", firstrow(variables) replace
restore
display "Tableau 4 (sans paludisme) exporte."


*----------------------------------------------------------------------
* FOREST PLOT - REPRODUCTIONS EXACTE DE IMAGE_A267E3.PNG
*----------------------------------------------------------------------

* Sauvegarder les coefficients du modèle
matrix b = e(b)
matrix V = e(V)

preserve
    clear
    set obs 7
    
    gen var = ""
    gen or = .
    gen ic_inf = .
    gen ic_sup = .
    gen pval = .
    
    local i = 1
    foreach var in age sexe_num fievre_aigue_bin cephalees_bin myalgies_bin nausees_vomissements_bin diarrhees_bin {
        local coef = _b[`var']
        local se = _se[`var']
        replace var = "`var'" in `i'
        replace or = exp(`coef') in `i'
        replace ic_inf = exp(`coef' - invnormal(0.975)*`se') in `i'
        replace ic_sup = exp(`coef' + invnormal(0.975)*`se') in `i'
        replace pval = 2*(1 - normal(abs(`coef'/`se'))) in `i'
        local i = `i' + 1
    }
    
    * Ordre des variables de haut en bas (Âge = 7 en haut, Diarrhées = 1 en bas)
    gen id = 8 - _n
    
    * Étiquettes de l'axe Y
    label define varlabels ///
        7 "Âge" ///
        6 "Sexe (masculin)" ///
        5 "Fièvre aiguë" ///
        4 "Céphalées" ///
        3 "Myalgies" ///
        2 "Nausées/vomissements" ///
        1 "Diarrhées"
    label values id varlabels
    
    * Plot Twoway
    twoway ///
        (rcap ic_inf ic_sup id, horizontal lcolor("10 40 80") lwidth(medium)) ///
        (scatter id or, msymbol(O) mcolor("10 40 80") msize(medium)), ///
        xline(1, lcolor(cranberry) lpattern(dash) lwidth(medium)) ///
        xscale(log) ///
        xlabel(0.4 "4 10^-1" 0.6 "6 10^-1" 1 "10^0", labsize(small) grid gstyle(dot)) ///
        ylabel(1/7, valuelabel angle(horizontal) labsize(small) nogrid) ///
        xtitle("Odds-ratio ajusté (IC 95%)", size(small)) ///
        ytitle("") ///
        title("Facteurs associés à la dengue confirmée", size(medium) color(black) style(bold)) ///
        subtitle("(modèle multivarié, n=1187)", size(small) color(black)) ///
        graphregion(color(white)) ///
        plotregion(color(white)) ///
        legend(off) ///
        name(forest_plot, replace)

* Exportation au format souhaité
graph export "$DOSSIER\Graphiques\Forest_Plot_Facteurs_Associes.png", replace width(2800) height(1800)

restore

display "Forest plot généré avec succès !"









*----------------------------------------------------------------------
* SECTION 10 : REGRESSIONS STRATIFIEES PAR STATUT PALUDISME
*----------------------------------------------------------------------
display "======================================================="
display " REGRESSIONS STRATIFIEES PAR STATUT PALUDISME"
display "======================================================="

display "--- CARACTERISTIQUES SELON LE STATUT PALUDISME ---"
tab test_paludisme_bin, missing
tab test_paludisme_bin dengue, row chi2

display "--- MODELE PALUDISME POSITIF ---"
count if test_paludisme_bin == 1 & !missing(dengue, age, sexe_num, fievre_aigue_bin, cephalees_bin, myalgies_bin, nausees_vomissements_bin, diarrhees_bin)
display "Effectif : " r(N)

logistic dengue age sexe_num fievre_aigue_bin cephalees_bin myalgies_bin ///
    nausees_vomissements_bin diarrhees_bin if test_paludisme_bin == 1, or
estimates store modele_palu_pos

display "--- MODELE PALUDISME NEGATIF ---"
count if test_paludisme_bin == 0 & !missing(dengue, age, sexe_num, fievre_aigue_bin, cephalees_bin, myalgies_bin, nausees_vomissements_bin, diarrhees_bin)
display "Effectif : " r(N)

logistic dengue age sexe_num fievre_aigue_bin cephalees_bin myalgies_bin ///
    nausees_vomissements_bin diarrhees_bin if test_paludisme_bin == 0, or
estimates store modele_palu_neg

display "--- COMPARAISON DES OR ENTRE LES DEUX GROUPES ---"
estimates table modele_palu_pos modele_palu_neg, b se p

preserve
    clear
    set obs 1
    gen Variable = ""
    gen OR_PaluPos = .
    gen ICinf_PaluPos = .
    gen ICsup_PaluPos = .
    gen OR_PaluNeg = .
    gen ICinf_PaluNeg = .
    gen ICsup_PaluNeg = .
    export excel using "$DOSSIER\Tableaux\Tableau4bis_Regressions_Stratifiees.xlsx", firstrow(variables) replace
restore
display "Tableau 4bis (modeles stratifies) exporte."

*----------------------------------------------------------------------
* SECTION 11 : MODELE AVEC INTERACTIONS
*----------------------------------------------------------------------
display "======================================================="
display " MODELE AVEC INTERACTIONS PALUDISME x SYMPTOMES"
display "======================================================="

logistic dengue age sexe_num fievre_aigue_bin cephalees_bin myalgies_bin ///
    nausees_vomissements_bin diarrhees_bin test_paludisme_bin ///
    fievre_aigue_bin#test_paludisme_bin ///
    cephalees_bin#test_paludisme_bin ///
    myalgies_bin#test_paludisme_bin ///
    diarrhees_bin#test_paludisme_bin, or

display "--- TEST GLOBAL DES INTERACTIONS ---"
testparm fievre_aigue_bin#test_paludisme_bin ///
    cephalees_bin#test_paludisme_bin ///
    myalgies_bin#test_paludisme_bin ///
    diarrhees_bin#test_paludisme_bin

*----------------------------------------------------------------------
* SECTION 12 : VALIDATION CROISEE STRATIFIEE
*----------------------------------------------------------------------
display "======================================================="
display " VALIDATION CROISEE STRATIFIEE"
display "======================================================="

set seed 123456
capture drop random sample_app
gen random = runiform()
gen byte sample_app = (random <= 0.7) if !missing(random)
tab sample_app

display "--- VALIDATION SUR PALUDISME POSITIF ---"
logistic dengue age sexe_num fievre_aigue_bin cephalees_bin myalgies_bin ///
    nausees_vomissements_bin diarrhees_bin if sample_app == 1 & test_paludisme_bin == 1, or

capture drop pred_pos
predict pred_pos if sample_app == 0 & test_paludisme_bin == 1
lroc if sample_app == 0 & test_paludisme_bin == 1
graph export "$DOSSIER\Graphiques\ROC_Logistique_Test_PaluPos.png", replace width(2000) height(1300)

display "--- VALIDATION SUR PALUDISME NEGATIF ---"
logistic dengue age sexe_num fievre_aigue_bin cephalees_bin myalgies_bin ///
    nausees_vomissements_bin diarrhees_bin if sample_app == 1 & test_paludisme_bin == 0, or

capture drop pred_neg
predict pred_neg if sample_app == 0 & test_paludisme_bin == 0
lroc if sample_app == 0 & test_paludisme_bin == 0
graph export "$DOSSIER\Graphiques\ROC_Logistique_Test_PaluNeg.png", replace width(2000) height(1300)

display "Validation croisee stratifiee terminee."

*----------------------------------------------------------------------
* SECTION 13 : CREATION DE LA SERIE MENSUELLE DES CAS SUSPECTS
*----------------------------------------------------------------------
use "$DOSSIER\Base_Dengue_Nettoyee.dta", clear

preserve
    keep if !missing(mtemp)
    gen byte suspect = 1
    collapse (sum) cas_suspects=suspect, by(mtemp)
    tsset mtemp, monthly
    tsfill
    replace cas_suspects = 0 if missing(cas_suspects)

    * ---------------------------------------------------------------
    * CORRECTION : juillet 2026 est un mois INCOMPLET (extraction faite
    * en tout debut de mois, 5 cas seulement contre plusieurs dizaines
    * habituellement). On le remet en donnee manquante pour qu'il soit
    * traite comme un mois A PREVOIR, et non comme un mois observe.
    * ---------------------------------------------------------------
    replace cas_suspects = . if mtemp == tm(2026m7)

    save "$DOSSIER\Base_Serie_Mensuelle_Suspects.dta", replace
restore

use "$DOSSIER\Base_Serie_Mensuelle_Suspects.dta", clear
list mtemp cas_suspects, sep(12)

twoway (tsline cas_suspects, color(navy) lwidth(medium)), ///
    title("Evolution mensuelle des cas suspects de dengue", size(medium)) ///
    subtitle("CHUR de Ouahigouya, 2024 - juin 2026 (juillet 2026 exclu, mois incomplet)", size(small)) ///
    xtitle("Mois", size(small)) ytitle("Nombre de cas suspects", size(small)) ///
    graphregion(color(white)) plotregion(color(white)) ///
    ylabel(, angle(horizontal) glcolor(gs14) glwidth(vthin))
graph export "$DOSSIER\Graphiques\Evolution_Mensuelle_Suspects.png", replace width(2000) height(1300)

display "Serie mensuelle des suspects sauvegardee et graphee (juillet 2026 exclu)."

*----------------------------------------------------------------------
* SECTION 14 : MODELE SARIMA ET PREVISIONS T3-T4 2026 (CAS SUSPECTS)
*----------------------------------------------------------------------
use "$DOSSIER\Base_Serie_Mensuelle_Suspects.dta", clear
tsset mtemp, monthly

* Dernier mois REELLEMENT observe = dernier mois avec cas_suspects non manquant
* (juin 2026 desormais, puisque juillet 2026 a ete mis en manquant ci-dessus)
qui summ mtemp if !missing(cas_suspects)
local dernier_mois_observe = r(max)
local horizon = ym(2026,12) - `dernier_mois_observe'
display "Dernier mois observe : " %tm `dernier_mois_observe'
display "Horizon de prevision necessaire (mois) : `horizon'"

* Estimation du modele SARIMA (l'estimation utilise automatiquement
* uniquement les mois non manquants, donc s'arrete a juin 2026)
arima cas_suspects, arima(1,1,1) sarima(1,0,0,12)
estimates store sarima_final

capture drop residus_suspects
predict residus_suspects, residuals
wntestq residus_suspects
tsline residus_suspects, title("Residus du modele SARIMA - Suspects", size(medium)) ///
    graphregion(color(white)) plotregion(color(white))
graph export "$DOSSIER\Graphiques\Residus_SARIMA_Suspects.png", replace width(2000) height(1300)

* La ligne de juillet 2026 existe deja (valeur manquante) : il ne faut
* ajouter que les mois APRES juillet, soit horizon-1 mois (aout a decembre)
local a_ajouter = `horizon' - 1
tsappend, add(`a_ajouter')

capture drop cas_prevu mse_prevu se_prevu ic_inf ic_sup
local premier_mois_prevu = `dernier_mois_observe' + 1

predict cas_prevu, y dynamic(`premier_mois_prevu')
predict mse_prevu, mse dynamic(`premier_mois_prevu')

gen se_prevu = sqrt(mse_prevu)
gen ic_inf = cas_prevu - 1.96 * se_prevu
gen ic_sup = cas_prevu + 1.96 * se_prevu

replace cas_prevu = 0 if cas_prevu < 0 & !missing(cas_prevu)
replace ic_inf = 0 if ic_inf < 0 & !missing(ic_inf)

format cas_prevu ic_inf ic_sup %6.1f

list mtemp cas_suspects cas_prevu ic_inf ic_sup if mtemp > `dernier_mois_observe', sep(0)

save "$DOSSIER\Base_Serie_Mensuelle_Suspects_avec_previsions.dta", replace

* --- Tableau 5 : previsions juillet-decembre 2026 ---
preserve
    keep if mtemp > `dernier_mois_observe' & year(dofm(mtemp)) == 2026
    gen mois = month(dofm(mtemp))
    gen trimestre = "T3 (juil-sept)" if inlist(mois,7,8,9)
    replace trimestre = "T4 (oct-dec)" if inlist(mois,10,11,12)
    keep mois trimestre cas_prevu ic_inf ic_sup
    order trimestre mois cas_prevu ic_inf ic_sup
    export excel using "$DOSSIER\Tableaux\Tableau5_Previsions_T3_T4_2026_Suspects_SARIMA.xlsx", firstrow(variables) replace
restore
display "Tableau 5 (Suspects - SARIMA, juillet inclus dans la prevision) exporte."

preserve
    keep if mtemp > `dernier_mois_observe' & year(dofm(mtemp)) == 2026
    gen mois = month(dofm(mtemp))
    qui summ cas_prevu if inlist(mois,7,8,9)
    display "Total prevu T3 2026 (juil-sept) : " %6.1f r(sum) " cas suspects"
    qui summ cas_prevu if inlist(mois,10,11,12)
    display "Total prevu T4 2026 (oct-dec) : " %6.1f r(sum) " cas suspects"
restore

*----------------------------------------------------------------------
* SECTION 15 : GRAPHIQUES DE PREVISION
*----------------------------------------------------------------------
qui summ mtemp if !missing(cas_suspects)
local dernier_mois_observe = r(max)

capture drop observe
capture drop prevu
gen byte observe = !missing(cas_suspects)
gen byte prevu = (mtemp > `dernier_mois_observe')

twoway ///
    (tsline cas_suspects if observe == 1, color(navy) lwidth(medium)) ///
    (tsline cas_prevu if prevu == 1, color(red) lwidth(medium) lpattern(dash)) ///
    (rarea ic_inf ic_sup mtemp if prevu == 1, color(red%15) lwidth(none)), ///
    title("Prevision des cas suspects de dengue - T3 et T4 2026", size(medium)) ///
    subtitle("Modele SARIMA(1,1,1)(1,0,0)[12] estime sur 2024-juin 2026", size(small)) ///
    xtitle("Mois", size(small)) ytitle("Nombre de cas suspects", size(small)) ///
    legend(order(1 "Observe" 2 "Prevu" 3 "IC 95%") position(6) rows(1)) ///
    graphregion(color(white)) plotregion(color(white)) ///
    ylabel(, angle(horizontal) glcolor(gs14) glwidth(vthin))
graph export "$DOSSIER\Graphiques\Prevision_T3_T4_2026_Suspects_SARIMA.png", replace width(2200) height(1400)

preserve
    keep if prevu == 1 & year(dofm(mtemp)) == 2026
    gen mois = month(dofm(mtemp))
    twoway ///
        (bar cas_prevu mois, color(red%60)) ///
        (rcap ic_inf ic_sup mois, color(gs6)), ///
        title("Previsions mensuelles detaillees - T3 et T4 2026 (Suspects)", size(medium)) ///
        xtitle("Mois", size(small)) ytitle("Nombre de cas suspects prevus", size(small)) ///
        xlabel(7(1)12, valuelabel) ///
        legend(order(1 "Prevision" 2 "IC 95%") position(6) rows(1)) ///
        graphregion(color(white)) plotregion(color(white)) ///
        ylabel(, angle(horizontal))
    graph export "$DOSSIER\Graphiques\Prevision_T3_T4_2026_Barres_Suspects_SARIMA.png", replace width(2000) height(1300)
restore

display "Graphiques de prevision (suspects - SARIMA, juillet inclus) generes."

*----------------------------------------------------------------------
* SECTION 16 : RESUME FINAL
*----------------------------------------------------------------------
use "$DOSSIER\Base_Dengue_Nettoyee.dta", clear
save "$DOSSIER\Base_Finale_Dengue.dta", replace

display "====================================================="
display " ANALYSE TERMINEE AVEC SUCCES"
display "====================================================="
display "Rappel : le dernier mois reellement observe est juin 2026."
display "Juillet 2026 (5 cas, mois incomplet dans l'extraction) est"
display "desormais PREVU au meme titre que le reste du 3e trimestre."

capture log close
display "FIN DE L'ANALYSE"
