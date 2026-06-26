je coris # Pipemind — Reste à faire
Branche de travail : `dev/justin`
Mis à jour : 2026-06-23

---

## Fait (cette session)

- [x] Infrastructure : `docker-compose.yml`, `.env.example`, `config/roster.example.json`
- [x] DB : migration `001-init-pipemind-schema.sql` — toutes les tables pipemind
- [x] **F-03** : Approval Gate (3 workflows : 01, 01b, 01c) — audité et durci par l'agent sécurité

---

## P0 — À construire maintenant

### Workflow 00 — Startup / Config Validation

Doit tourner au démarrage de n8n et toutes les 5 min.

- Lire `/config/roster.json`
- Valider le JSON (champs requis : name, discord_id, role, clockify_user_id)
- Upsert toutes les entrées dans `pipemind.roster`
- Mettre `system_state.roster_valid = 'true'`
- **Fail visible** si le fichier est absent ou invalide (SC-19)

### F-08 — Aggregation Boundary (nœud d'audit)

Prérequis pour F-01, F-02, F-15.

- Nœud Code réutilisable qui vérifie le draft_text avant appel à F-03
- Bloque si le texte contient une attribution individuelle (nom, discord_id, chiffres par dev)
- Retourne `boundary_audit_passed: true` seulement si le texte est 100 % projet-level
- Inclure le system prompt Ollama qui force l'agrégation

### F-16 — Team Lead Interaction (Discord listener)

- Écouter le channel TL restreint sur Discord
- Commandes : `/status`, `/report`, `/qa`, `/help`
- Toutes les réponses passent par F-03 (draft → approbation → envoi)

### F-01 — Client Report

- Déclenché par `REPORT_DAY_TIME` (vendredi 17:00)
- Agréger les signaux (GitHub, Jira — feature-level seulement, jamais individuel)
- Passer par F-08 → F-03 → livraison Drive + Gmail

### F-02 — Client Q&A

- Écouter le channel client Discord
- LLM génère une réponse projet-level
- Passer par F-08 → F-03 → livraison discord_qa

### F-15 — Client Welcome

- Déclenché une seule fois par client (table `client_welcomed` protège contre le doublon)
- Passer par F-03 → livraison discord_welcome
- Mettre à jour `client_welcomed` après envoi

### F-17 — Developer Queries

- Écouter les DMs des devs
- Répondre à des questions sur leur propre agenda, Clockify, calendrier
- Données individuelles restent dans le DM — jamais agrégées vers le TL

---

## P1 — Après P0

### F-14 — Persistent Memory (Postgres)

- Stocker le contexte conversationnel par dev / par projet
- Needed pour Q&A contextuel (F-02) et check-ins (F-05)

### F-04 — Standup Ingestion

- Surveiller Google Drive (dossier `DRIVE_FOLDER_ID`) pour de nouveaux transcripts
- Parser, anonymiser, stocker dans Postgres
- Nourrir F-01 et F-16

### F-05 — Check-ins Développeurs

- DM optionnel à chaque dev le matin (vérifier Clockify/Calendar avant)
- **SC-06** : contacter seulement les gens schedulés ce jour-là
- Le dev peut répondre ou ignorer — jamais de relance

### F-07 — Time-Logging Helper

- En fin de journée (`EOD_TIME`)
- Suggérer des entrées Clockify basées sur Git/Calendar
- Draft → approbation dev → écriture Clockify (write approuvé uniquement)

---

## Beyond P1

### F-06 — Unblock Assistance

- Détecter des patterns de blocage (ex. PR en review depuis 2 jours)
- Proposer de l'aide au dev concerné (DM uniquement)
- Jamais de remontée individuelle au TL

---

## Dettes techniques / Sécurité

| Priorité | Item                                      | Détail                                                                                                                      |
| -------- | ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| MED      | HIGH-04 : Validation channel draft expiré | Dans 01b, `Notify Expired` envoie au `discord_channel_id` du draft — pas de validation que ce channel est encore accessible |
| LOW      | Workflow 06 — Expiry Janitor              | Tâche cron qui passe les drafts `pending` expirés à `expired` dans la DB                                                    |
| LOW      | Docker network `internal: false`          | Le réseau pipemind-internal est accessible depuis l'hôte — à durcir avant prod                                              |

---

## Ordre recommandé

```
Workflow 00 → F-08 → F-16 → F-01 → F-02 → F-15 → F-17
                                                         ↓
                                             Workflow 06 (janitor)
                                                         ↓
                                              P1 : F-14 → F-04 → F-05 → F-07
```

> Rappel : après chaque feature, appeler l'agent `security` avant de committer.
