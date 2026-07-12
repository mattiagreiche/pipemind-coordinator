# Pipemind — Plan de test end-to-end

*Créé le 2026-07-11, mis à jour le même soir après la première vraie session de test.
Répartition des tests entre Justin et Mattia selon les rôles définis dans `config/roster.json`.*

**Important** : Justin et Mattia font chacun tourner leur **propre instance locale séparée**
(Docker/Postgres/n8n indépendants) — un fix appliqué chez l'un ne s'applique pas automatiquement
chez l'autre. Chacun doit `git pull` + réimporter les workflows modifiés dans son propre n8n.
Les deux instances partagent en revanche le **même token de bot Discord** (voir "Blocages connus"
plus bas — piste probable pour le bug de réactions).

## Qui teste quoi

### Justin — rôle `team_lead`

Teste tout ce qui s'adresse au Team Lead, avec son propre compte Discord (celui
enregistré comme `team_lead` dans le roster).

| Workflow | Comment tester | État |
|---|---|---|
| `03 — F-16: Team Lead Interaction` | Écrire dans `#tl-approvals` (ex: "what's the project status", "explain what you do") | ✅ Testé, fonctionne (2026-07-11) |
| `04 — F-01: Client Progress Report` (on-demand) | Écrire "generate the weekly report" dans `#tl-approvals` (passe par `03`) | ✅ Testé, fonctionne (2026-07-11) — premier draft client de l'histoire du projet généré |
| Approval Gate (F-03) — réagir sur un draft | Réagir ✅ / ✏️ / ❌ sur n'importe quel draft posté dans `#tl-approvals` | ❌ **Bloqué** — la réaction ne remonte jamais jusqu'à `01b` (voir "Blocages connus") |

### Mattia — rôle `developer`

Teste tout ce qui s'adresse à un développeur, avec son propre compte Discord
(celui enregistré comme `developer` dans le roster).

| Workflow | Comment tester | État |
|---|---|---|
| `07 — F-17: Developer Project-Status Query` | DM au bot ("what's the project status", "explain what you do") | ✅ Bug pairedItem corrigé (commit `3dd8e11`) — à retester après `git pull` |
| `10 — F-05: Developer Check-In` | Attendre le déclenchement automatique, ou trigger manuel dans l'UI | ⚠️ Bloqué — `CLOCKIFY_WORKSPACE_ID` non configuré |
| `11 — F-07: Time-Log Offer (EOD)` | Attendre `EOD_TIME`, ou trigger manuel | ⚠️ Bloqué — Clockify |
| `12 — F-06: Unblock Assistance` | Répondre "yes"/"colleague"/"meeting"/"just-talk" à une offre d'aide | ⚠️ Bloqué — Clockify |

### Mattia jouant le rôle "Client"

Comme il n'y a pas de vraie personne cliente pour l'instant, Mattia peut simuler
ce rôle en écrivant dans le channel client (`CLIENT_CHANNEL_ID`, `#client`).
Ces workflows se déclenchent sur le **channel**, pas sur une identité Discord
précise — n'importe qui avec accès au channel peut tester.

| Workflow | Comment tester | État |
|---|---|---|
| `05 — F-02: Client Question Answering` | Poser une question dans `#client` (ex: "what's the status of the auth feature") | ✅ Bug pairedItem corrigé (commit `3dd8e11`) — à retester après `git pull`. Note : un draft `qa_reply` a déjà été généré avec succès sur l'instance de Mattia le 2026-07-11 avant même ce fix — donc ce chemin précis ne l'avait peut-être pas touché. |
| `06 — F-15: Client Welcome Message` | Se joindre au channel `#client` / premier message | ✅ Bug pairedItem corrigé (commit `3dd8e11`) — à retester après `git pull` |

## Blocages connus (mis à jour 2026-07-11 fin de soirée)

1. **Les réactions Discord (✅/❌/✏️) ne remontent jamais jusqu'à `01b`** — **priorité #1**.
   Piste probable : Justin et Mattia partagent le même token de bot Discord sur deux instances
   locales séparées, ce qui peut causer une livraison d'événements Gateway incohérente (une
   session "vole" des événements sans erreur visible). Les messages texte fonctionnent
   parfaitement ; seules les réactions sont perdues. Webhook `approval-resolution` confirmé
   bien enregistré côté n8n — donc probablement pas un bug de workflow. À vérifier en premier :
   couper un des deux `discord-forwarder` et retester.
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
6. **IF natifs non audités dans `01`/`01b`/`01c`** — le bug de comparateur n8n 1.91.3 touche
   plus de types (string/number, pas juste booléen) qu'initialement documenté. Ce chemin
   (approval gate + delivery) n'a jamais été vérifié pour ce pattern.

## Notes

- Chaque instance (Justin, Mattia) tourne sa propre stack Docker locale complètement
  séparée — vérifier les résultats dans SA PROPRE base (`execution_entity`), pas celle
  de l'autre.
- Après chaque exécution, on peut vérifier le résultat directement en base
  (`execution_entity`) sans dépendre uniquement de l'UI.
- Détail complet des bugs trouvés/corrigés le 2026-07-11 : voir `RESTE_A_FAIRE.md`
  section "5. Bugs trouvés le 2026-07-11".
