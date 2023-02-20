# checkconf
Make a diff between CBS/PSI configuration keys from database and keys from files (asc or fcv).

Voici les améliorations :

1) checkconf nomDeFichier.asc (ou nomDeFichier.fcv)   ... exemple : "checkconf /pica/users/r_cbs/ab/asc/nomDeFichier.asc"  ou "checkconf ./ab/asc/nomDeFichier.asc" ou directement "checkconf nomDeFichier.fcv" si on se trouve dans le répertoire du fichier.
- Affichage d'un message "fichier OK" ou "fichier Différent"
- Correction d'un bug au niveau des couleurs du diff. Rappel du principe général à retenir au niveau des couleurs : On se place dans l'hypothèse qu'on compile le fichier .. En rouge tout ce qui sera supprimé en mémoire et en bleu tout ce qui sera ajouté en mémoire. 
- Affichage en mode page (commande more) pour les diff long
- Affichage en fin de programme des noms des fichiers à analyser si besoin.

2) checkconf ./nomDeRépertoire (répertoire contenant des *.asc ou *.fcv). exemple "checkconf /pica/users/r_cbs/ab/fcv" ou "checkconf ./ab/fcv" ou encore "checkconf ./" si on se trouve dans le répertoire en question. Pour rappel cette commande créera un rapport sous la forme d'un fichier csv nommé "fileskeys.csv". Le chemin d'accès à ce fichier est affiché en fin de programme.
- Amélioration de l'affichage du rapport en utilisant un fichier excel contenant une macro de mise en forme automatique. Ce fichier excel se nomme "mise_en_forme-v3.xlsm" et se trouve au même niveau que le fichier fileskeys.csv. Le principe d'utilisation demande 3 actions mais reste simple et rapide. Voici le mode d'emploi : ouvrir dans excel "fileskeys.csv" et faire "ctrl C" pour copier toutes les données, puis ouvrir dans excel le fichier "mise_en_forme-v3.xlsm", accepter l'activation des macros, coller les données dans l'onglet fileskeys et lancer la macro avec un "ctrl M". (en pièce jointe le fichier mise_en_forme-v3.xlsx "-sans macro-" avec les données de Rubeus répertoire ab/asc)
- Suppression des faux doublons dans les résultats

3)  checkconf -w ./nomDeRépertoire (répertoire contenant des *.asc uniquement)
L'option -w réécrit les fichiers de configuration à partir des informations se trouvant en mémoire (par un tbtoasc). Ces nouveaux fichiers de conf sont stockés dans le répertoire ...ab/scripts/checkconf/Repport/Write. Un tar gz de l'arborescence d'origine est stocké dans le répertoire Repport au même niveau que le répertoire Write.
- L'entête/commentaire se trouvant en début des fichiers de configuration d'origine est conservé dans les fichiers créés.
- Une nouvelle ligne de commentaire est ajouté en fin d'entête des fichiers créés avec les informations suivantes : "!  $(stamp)	:  checkconf  :  rewrite of key values ​​by tbtoasc - $fileName "
