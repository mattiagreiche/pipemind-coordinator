# Pipemind — Plan de test end-to-end

*Créé le 2026-07-11, mis à jour le 2026-07-13 (soir) après la session qui a trouvé la vraie
cause probable du bug des réactions (voir point 1 de "Blocages connus"). Répartition des tests
entre Justin et Mattia selon les rôles définis dans `config/roster.json`.*

**Important** : Justin et Mattia font chacun tourner leur **propre instance locale séparée**
(Docker/Postgres/n8n indépendants) — un fix appliqué chez l'un ne s'applique pas automatiquement
chez l'autre. Chacun doit `git pull` + réimporter les workflows modifiés dans son propre n8n
(voir la commande `n8n import:workflow --input=...` + réactivation + **redémarrage du conteneur
n8n obligatoire** pour que l'activation prenne effet). Les credentials Google (Drive/Calendar/
Gmail) sont **spécifiques à chaque instance** — voir point 7 de "Blocages connus", important
avant de retester `01b`/`01c`. Les deux instances partagent le même token de bot Discord ; ce
n'est probablement plus considéré comme la cause du bug de réactions (voir point 1).

## Qui teste quoi

### Justin — rôle `team_lead`

Teste tout ce qui s'adresse au Team Lead, avec son propre compte Discord (celui
enregistré comme `team_lead` dans le roster).

| Workflow | Comment tester | État |
|---|---|---|
| `03 — F-16: Team Lead Interaction` | Écrire dans `#tl-approvals` (ex: "what's the project status", "explain what you do") | ✅ Testé, fonctionne (2026-07-11, reconfirmé 2026-07-13) |
| `04 — F-01: Client Progress Report` (on-demand) | Écrire "generate the weekly report" dans `#tl-approvals` (passe par `03`) | ✅ Testé, fonctionne (2026-07-11, reconfirmé 2026-07-13) |
| Approval Gate (F-03) — réagir ✅ (approve) sur un draft `report` | Réagir ✅ sur un draft posté dans `#tl-approvals` | ✅ Validé le 2026-07-13 mais **via webhook simulé seulement** (Claude, pas une vraie réaction Discord) — à reconfirmer avec un vrai clic ✅. Livraison Drive bloquée séparément (credential sans token valide, voir "Blocages connus") |
| Approval Gate (F-03) — réagir ❌ (reject) / ✏️ (edit) | Réagir ❌ ou ✏️ sur un draft | ⚠️ **Pas encore testé du tout**, même via simulation — priorité #1 de la prochaine session |

### Mattia — rôle `developer`

Teste tout ce qui s'adresse à un développeur, avec son propre compte Discord
(celui enregistré comme `developer` dans le roster).

| Workflow | Comment tester | État |
|---|---|---|
| `07 — F-17: Developer Project-Status Query` | DM au bot ("what's the project status", "explain what you do") | ✅ Bug pairedItem corrigé (commit `3dd8e11`) — à retester après `git pull` |
| `10 — F-05: Developer Check-In` | Attendre le déclenchement automatique, ou trigger manuel dans l'UI | ⚠️ Bloqué — `CLOCKIFY_WORKSPACE_ID` non configuré |
| `11 — F-07: Time-Log Offer (EOD)` | Attendre `EOD_TIME`, ou trigger manuel | ⚠️ Bloqué — Clockify |
| `12 — F-06: Unblock Assistance` | Répondre "yes"/"colleague"/"meeting"/"just-talk" à une offre d'aide | ⚠️ Bloqué — Clockify (le workflow 12 qui *envoie* l'offre). Le traitement de la réponse côté `01b` a eu un bug de branches inversées (offre trouvée → skip au lieu de traiter) corrigé le 2026-07-13, mais **jamais testé en conditions réelles**, même via simulation — priorité #1 de la prochaine session, avec les fixs `01b` de ce soir |

### Mattia jouant le rôle "Client"

Comme il n'y a pas de vraie personne cliente pour l'instant, Mattia peut simuler
ce rôle en écrivant dans le channel client (`CLIENT_CHANNEL_ID`, `#client`).
Ces workflows se déclenchent sur le **channel**, pas sur une identité Discord
précise — n'importe qui avec accès au channel peut tester.

| Workflow | Comment tester | État |
|---|---|---|
| `05 — F-02: Client Question Answering` | Poser une question dans `#client` (ex: "what's the status of the auth feature") | ✅ Bug pairedItem corrigé (commit `3dd8e11`) — à retester après `git pull`. Note : un draft `qa_reply` a déjà été généré avec succès sur l'instance de Mattia le 2026-07-11 avant même ce fix — donc ce chemin précis ne l'avait peut-être pas touché. Un 2e bug (résidu d'auth cassé sur `Check Candidate Scheduled`, chemin teammate-escalation F-02.2/F-02.3) corrigé le 2026-07-13, pas encore testé. |
| `06 — F-15: Client Welcome Message` | Se joindre au channel `#client` / premier message | ✅ Bug pairedItem corrigé (commit `3dd8e11`) — à retester après `git pull` |

## Blocages connus (mis à jour 2026-07-13 soir)

1. **Les réactions Discord (✅/❌/✏️) ne remontaient jamais jusqu'à `01b`** — **priorité #1**,
   probablement réglée le 2026-07-13. Le 2026-07-11, la théorie était un token de bot Discord
   partagé entre Justin et Mattia sur deux instances locales. Cette théorie n'a jamais été
   vérifiée directement — en testant `01b` en direct (webhook simulé, contournant Discord), on a
   trouvé que le node `Classify Event` ne déballait jamais le wrapper `.body` du webhook n8n,
   donc TOUT événement (réaction ou message) tombait systématiquement en `skip: true`. Ce bug de
   code suffit à expliquer tout le symptôme observé — corrigé. **Reste à confirmer avec une vraie
   réaction Discord** (pas encore fait) avant de considérer ça définitivement réglé. Voir
   `RESTE_A_FAIRE.md` section "Tests end-to-end 01b/01c" pour le détail complet.
2. **Bug pairedItem `.item`/`.first()`** — corrigé partout (`03`: commit `59bea5d`,
   `05`/`06`/`07`: commit `3dd8e11`). Chaque instance doit `git pull` + réimporter pour en
   bénéficier.
3. **`CLOCKIFY_WORKSPACE_ID` non configuré** — bloque `10`, `11`, `12`, `01b`, `01c`
   (fail visiblement, par design).
4. **Jira / GitHub non configurés** — dégradent proprement (signal secondaire seulement,
   jamais bloquant).
5. **Incohérence de langue** — messages codés en dur en français/anglais mélangés, contenu
   généré par Ollama en anglais par défaut (system prompt ne spécifie aucune langue cible).
   Pas bloquant, à uniformiser.
6. **IF natifs dans `01`/`01b`/`01c`** — audité et corrigé le 2026-07-13 (31 nodes convertis,
   voir `RESTE_A_FAIRE.md`). Plus un blocage.
7. **Les credentials Google (Calendar/Drive/Gmail) ont un ID différent sur chaque instance —
   important pour Mattia avant de retester `01b`/`01c` après ce `git pull`.** n8n génère un ID
   aléatoire à la création de chaque credential ; il n'y a **aucun fallback automatique** si
   l'ID référencé dans le JSON n'existe pas localement (confirmé ce soir : erreur franche
   `"Credential with ID X does not exist"`, pas de résolution par nom ou par type). Concrètement,
   après ce `git pull` + réimport, Mattia va très probablement retomber sur la même erreur que
   Justin ce soir, car les IDs corrigés dans le JSON (`QLPhcT7Vchnjrqsp` pour Calendar,
   `SAyj8Ovli7hMCL9c` pour Drive) sont ceux de **l'instance de Justin**, pas de la sienne. Pour
   corriger côté Mattia :
   - Créer/vérifier ses propres credentials n8n (Google Drive OAuth2, Google Calendar OAuth2 —
     Gmail n'existe même pas encore chez Justin, à créer des deux côtés)
   - Dans l'UI n8n, ouvrir chaque node concerné (`Save to Drive`, `Create Calendar Event`,
     `Check Colleague Calendar OOO`, `Send Gmail`) et sélectionner le bon credential dans le menu
     déroulant — ça met à jour l'ID en base **localement**, sans toucher au fichier JSON
   - ⚠️ Un futur `git pull` + réimport écrasera à nouveau ce choix local avec l'ID de Justin —
     c'est exactement le piège qui a cassé Drive ce soir (un fix manuel antérieur, jamais commité,
     écrasé par un réimport). Si ça devient récurrent, il faudra soit committer les vrais IDs de
     chaque instance dans des fichiers `.env`-like séparés, soit ne plus réimporter ces 2-3 nodes
     depuis le JSON une fois configurés localement.

## Notes

- Chaque instance (Justin, Mattia) tourne sa propre stack Docker locale complètement
  séparée — vérifier les résultats dans SA PROPRE base (`execution_entity`), pas celle
  de l'autre.
- Après chaque exécution, on peut vérifier le résultat directement en base
  (`execution_entity`) sans dépendre uniquement de l'UI.
- Détail complet des bugs trouvés/corrigés le 2026-07-11 : voir `RESTE_A_FAIRE.md`
  section "5. Bugs trouvés le 2026-07-11".
