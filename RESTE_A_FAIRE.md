# Reste à faire — Pipemind Coordinator

## Priorité immédiate — Débloquer le pipeline complet

### 1. Credentials manquants (workflow 05 s'arrête à Fetch GitHub Signals)
- [ ] **GitHub token** : ajouter `GITHUB_TOKEN` valide dans `.env` + vérifier `GITHUB_OWNER` / `GITHUB_REPO`
- [ ] **Jira** : ajouter `JIRA_BASE_URL`, `JIRA_TOKEN`, `JIRA_AUTH`, `JIRA_PROJECT_KEY` dans `.env`
- [ ] **Ollama** : télécharger un modèle — `docker exec pipemind-coordinator-ollama-1 ollama pull llama3.2`

### 2. Google OAuth (workflow 09 — standup ingestion)
- [ ] Finaliser l'app Google OAuth (actuellement en mode "test")
- [ ] Ajouter l'email test dans Google Auth Platform → Audience
- [ ] Se connecter dans n8n Settings → Credentials → Google Docs OAuth2
- [ ] Récupérer le credential ID et l'ajouter aux noeuds qui l'utilisent dans workflow 09

### 3. Variables d'environnement post-import
Après chaque réimport de workflows, mettre à jour `.env` avec les nouveaux IDs :
- [ ] `F03_WORKFLOW_ID` — ID du workflow 01 (Approval Gate)
- [ ] `F08_WORKFLOW_ID` — ID du workflow 02 (Aggregation Boundary)
- [ ] `F01_WORKFLOW_ID` — ID du workflow 04 (Client Report)
- [ ] `DELIVERY_EXECUTOR_WORKFLOW_ID` — ID du workflow 01c
- [ ] Redémarrer n8n après mise à jour : `docker compose restart n8n`

### 4. Activer les workflows restants
- [ ] Workflow 01 — Approval Gate (sub-workflow, pas de trigger, activé via Execute Workflow)
- [ ] Workflow 01b — Approval Resolution Listener (webhook, doit être actif pour recevoir les réactions Discord)
- [ ] Workflow 01c — Delivery Executor (sub-workflow)
- [ ] Workflow 02 — Aggregation Boundary (sub-workflow)
- [ ] Workflow 04 — Client Report (schedule trigger vendredi 17h)

### 5. Discord Privileged Intents à confirmer
- [ ] Vérifier dans Discord Developer Portal → Bot → Privileged Gateway Intents :
  - Message Content Intent ✓ (requis pour lire le contenu des messages)
  - Server Members Intent ✓ (requis pour GUILD_MEMBER_ADD)

---

## À tester end-to-end (une fois credentials OK)

1. **Client Q&A** : envoyer message dans `#client` → draft dans `#tl-approvals` → réagir ✅ → réponse dans `#client`
2. **Client Welcome** : nouveau membre rejoint → draft bienvenue dans `#tl-approvals` → approuver → message de bienvenue
3. **Developer Query** : DM au bot → réponse directe
4. **TL Interaction** : message dans `#tl-approvals` → workflow 03 classifie l'intent
5. **Client Report** : déclencher workflow 04 manuellement → draft rapport dans `#tl-approvals`

---

## Bugs IF node connus (à garder en tête)

Dans n8n 1.91.3, les IF nodes avec comparaison booléenne (`=== true`) se comportent de manière
imprévisible. **Pattern à utiliser à la place :**
- Dans les Code nodes : `return []` pour stopper, `return $input.all()` pour continuer
- Éviter les IF nodes pour les checks de type boolean ou count

Workflows déjà corrigés avec ce pattern : 03, 05, 06, 07
Workflows à vérifier si d'autres IF nodes causent des problèmes : 01b, 03 (Response Clean?), 07 (Response Clean?, Draft Found?, etc.)

---

## Infrastructure

- [ ] Configurer backup automatique Postgres
- [ ] Passer Ollama en mode GPU si disponible (décommenter section dans docker-compose.yml)
- [ ] Mettre en place monitoring des workflows (alertes sur erreurs répétées)
