# Pipemind — Plan de test end-to-end

*Créé le 2026-07-11. Répartition des tests entre Justin et Mattia selon les rôles
définis dans `config/roster.json`.*

## Qui teste quoi

### Justin — rôle `team_lead`

Teste tout ce qui s'adresse au Team Lead, avec son propre compte Discord (celui
enregistré comme `team_lead` dans le roster).

| Workflow | Comment tester | État |
|---|---|---|
| `03 — F-16: Team Lead Interaction` | Écrire dans `#tl-approvals` (ex: "what's the project status", "explain what you do") | ✅ Testé, fonctionne (2026-07-11) |
| Approval Gate (F-03) | Réagir ✅ / ✏️ / ❌ sur n'importe quel draft posté dans `#tl-approvals`, peu importe le workflow d'origine (client report, client Q&A, time-log, etc.) | À tester dès qu'un draft est généré |
| `04 — F-01: Client Progress Report` (on-demand) | Déclencher via le trigger à la demande dans l'UI n8n, ou attendre le scheduler du vendredi | Non testé |

### Mattia — rôle `developer`

Teste tout ce qui s'adresse à un développeur, avec son propre compte Discord
(celui enregistré comme `developer` dans le roster).

| Workflow | Comment tester | État |
|---|---|---|
| `07 — F-17: Developer Project-Status Query` | DM au bot ("what's the project status", "explain what you do") | ⚠️ Bloqué — même bug pairedItem que `03` (pas encore corrigé) |
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
| `05 — F-02: Client Question Answering` | Poser une question dans `#client` (ex: "what's the status of the auth feature") | ⚠️ Bloqué — même bug pairedItem que `03` (pas encore corrigé) |
| `06 — F-15: Client Welcome Message` | Se joindre au channel `#client` / premier message | ⚠️ Bloqué — même bug pairedItem que `03` (pas encore corrigé) |

## Blocages connus (2026-07-11)

1. **Bug pairedItem `.item`/`.first()`** — corrigé dans `03` ce soir (commit `59bea5d`).
   Le même pattern existe dans `05`, `06`, `07` (nodes `Verify Client`, `Verify Client
   Join`, `Verify Developer`) — pas encore corrigé. Toute tentative de test sur ces
   3 workflows va planter avec une erreur n8n trompeuse ("please unpin ... and try
   again", qui n'a rien à voir avec du pinned data réel).
2. **`CLOCKIFY_WORKSPACE_ID` non configuré** — bloque `10`, `11`, `12`, `01b`, `01c`
   (fail visiblement, par design).
3. **Jira non configuré** — dégrade proprement (signal secondaire seulement, jamais
   bloquant).
4. **`GITHUB_OWNER`/`GITHUB_REPO` non configurés** — dégrade proprement (signal
   secondaire seulement, jamais bloquant).

## Notes

- Chaque test déclenche un vrai message Discord / vraie exécution n8n sur
  l'instance de Justin (`localhost:5678`) — pas d'environnement de test séparé.
- Après chaque exécution, on peut vérifier le résultat directement en base
  (`execution_entity`) sans dépendre uniquement de l'UI.
- Ce fichier n'est pas commité automatiquement — dis-le si tu veux qu'il aille
  dans le repo.
