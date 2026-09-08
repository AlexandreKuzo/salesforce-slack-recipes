# Salesforce Slack Recipes (SSR Stack)

Pack déployable d'intégration **Salesforce ↔ Slack** via Bot API : Flows, Apex, Custom Metadata et recettes incrémentales.

> **État actuel :** recettes **01**, **02**, **07**, **08** et **10** disponibles. Les autres recettes arrivent progressivement — suivez le repo pour les releases.

## Prérequis

- Org Salesforce (Developer, Sandbox ou Production) avec Apex et Flow
- [Salesforce CLI](https://developer.salesforce.com/tools/sfdxcli) (`sf`)
- Slack App avec Bot Token (`xoxb-...`) et scope `chat:write`

## Démarrage rapide

```bash
git clone https://github.com/AlexandreKuzo/salesforce-slack-recipes.git
cd salesforce-slack-recipes
sf org login web --alias my-org
sf project deploy start --manifest manifest/ssr-recipe01-package.xml --target-org my-org
```

Après le déploiement de la recette 01 :

1. **Setup → Custom Settings → SSR Slack Settings** : renseigner le `Bot Token`
2. **Setup → Custom Metadata Types → SSR Slack Recipe** : remplacer `C0123456789` par l'ID de votre channel Slack
3. Inviter le bot dans le channel concerné
4. Assigner le Permission Set `SSR_Slack_User` aux utilisateurs qui déclenchent les flows
5. **Activer** le Flow `SSR Recipe 01 - Alerte Nouvelle Opportunite`

Pour la recette 02 :

```bash
sf project deploy start --manifest manifest/ssr-recipe02-package.xml --target-org my-org
```

Puis mettre à jour l'enregistrement CMDT `recipe_02` et activer le Flow associé.

Pour la recette 07 (création dynamique de channel) :

```bash
sf project deploy start --manifest manifest/ssr-recipe07-package.xml --target-org my-org
```

Cette recette ne route pas via un channel fixe : elle **crée** un channel `deal-<account>-<année>` quand une opportunité passe en Closed Won, puis y invite l'owner et son manager (matching par email Slack).

1. Scopes bot supplémentaires : `channels:manage`, `channels:read`, `users:read.email`
2. Renseigner le champ **Manager** de l'utilisateur owner (optionnel — sinon seul l'owner est invité)
3. Les emails Salesforce (owner/manager) doivent exister dans le workspace Slack
4. Assigner le Permission Set `SSR_Slack_User` (inclut la FLS lecture seule du champ `Opportunity.SlackChannelId__c`)
5. **Activer** le Flow `SSR Recipe 07 - Creation Channel Slack`

Le champ `SlackChannelId__c` est en **lecture seule** : il est alimenté automatiquement par l'intégration Apex, jamais manuellement.

Pour la recette 08 (résumé IA d'un Case en DM Slack) :

```bash
sf project deploy start --manifest manifest/ssr-recipe08-package.xml --target-org my-org
```

Cette recette **ne poste pas dans un channel fixe** : elle résume le Case (OpenAI si clé configurée, sinon fallback rule-based), résout l'**owner** Slack via `users.lookupByEmail`, puis envoie un **DM**.

1. Scope bot supplémentaire : `users:read.email` (déjà requis pour la recette 07)
2. Optionnel : Setup → **SSR Slack Settings** → renseigner **OpenAI API Key** (`sk-...`)
3. L'email Salesforce de l'owner du Case doit exister dans le workspace Slack
4. Assigner le Permission Set `SSR_Slack_User`
5. **Activer** le Flow `SSR Recipe 08 - Resume Case IA`
6. Ajouter le Quick Action `Escalader ce Case` (`Case.SSR_Escalate_Case`) sur la page Case — Setup → **Object Manager** → **Case** → **Page Layouts** (ou **Lightning App Builder** → panneau Highlights) → glisser l'action dans la section « Salesforce Mobile and Lightning Experience Actions »

`IsEscalated` est un champ standard **non exposé en édition libre** dans ce projet (volontairement — voir note ci-dessous). Ce Quick Action coche le champ de façon contrôlée, sans exposer d'autre champ en édition.

> **Pourquoi un Quick Action plutôt qu'une checkbox éditable ?** De nombreuses orgs retirent `IsEscalated` du layout pour éviter des escalades manuelles incohérentes, et pilotent l'escalade soit automatiquement (Setup → **Escalation Rules**, basées sur des délais SLA), soit via une action métier contrôlée comme celle-ci. Le Quick Action déclenche exactement le même Flow que l'escalade automatique.
>
> **Le déclencheur du Flow est personnalisable.** `SSR_Recipe08_Case_AI_Summary` se lance sur `IsEscalated = true` OU `OwnerId` changé — mais ces critères d'entrée se modifient librement dans Flow Builder (par exemple : uniquement sur changement de Priority, sur un champ personnalisé `Need_AI_Summary__c`, ou sur tout autre événement Case pertinent pour votre process).

Pour la recette 10 (qualification et routage de lead) :

```bash
sf project deploy start --manifest manifest/ssr-recipe10-package.xml --target-org my-org
```

Cette recette **score** chaque nouveau Lead (OpenAI `gpt-4o-mini` si clé configurée, sinon fallback règles secteur + effectif via CMDT), écrit `Score__c` / `AI_Reasoning__c` / `Confidence__c` / `Scored_At__c`, puis **route** selon deux seuils (`SSR_Lead_Scoring_Config__mdt`) :

| Score | Routage |
|-------|---------|
| ≥ seuil haut (défaut 70) | **HOT** — réassignation à `Hot_Lead_Owner_Id__c` (si renseigné) + Task « Rappeler sous 1h » |
| entre les deux seuils | **NURTURE** — ajout à `Nurture_Campaign_Id__c` (si renseignée) |
| < seuil bas (défaut 40) | **DISQUALIFIED** — `Disqualification_Reason__c` renseigné ; `Lead.Status` passé à `Disqualified_Status__c` (si renseigné) |

Notification : Slack via `SlackService` si la clé `Slack_Recipe_Key__c` (défaut `recipe_10`) résout un channel dans `SSR_Slack_Recipe__mdt` ; sinon **e-mail** à l'owner du Lead (fallback natif).

1. Scope bot Slack : `chat:write` (déjà requis pour la recette 01)
2. Optionnel : Setup → **SSR Slack Settings** → renseigner **OpenAI API Key** (`sk-...`) — sans clé, le scoring reste fonctionnel en mode règles
3. Remplacer `C0123456789` dans l'enregistrement CMDT `SSR_Slack_Recipe.recipe_10` par l'ID de votre channel (ou vider `Slack_Recipe_Key__c` pour forcer le fallback e-mail)
4. Ajuster `SSR_Lead_Scoring_Config.default` (seuils, cible d'assignation, campagne, ICP) et enrichir `SSR_Lead_Industry_Score` (points par secteur)
5. Assigner le Permission Set `SSR_Slack_User` (inclut la FLS lecture seule des 5 champs `Lead`)
6. **Activer** le Flow `SSR Recipe 10 - Lead Qualification` (livré en *Draft*)

Le Flow se déclenche à la création d'un Lead (ou sur un Lead encore non scoré) ayant une `Company`. Les critères d'entrée se personnalisent librement dans Flow Builder.

## Recettes

| # | Statut | Manifest | Description |
|---|--------|----------|-------------|
| 01 | ✅ Disponible | `manifest/ssr-recipe01-package.xml` | Socle Apex + alerte nouvelle opportunité |
| 02 | ✅ Disponible | `manifest/ssr-recipe02-package.xml` | Alerte changement de stage |
| 03 | 🔜 Bientôt | — | Escalade support |
| 04 | 🔜 Bientôt | — | Closed Won manager |
| 05 | 🔜 Bientôt | — | Approbation devis |
| 06 | 🔜 Bientôt | — | Commande expédiée |
| 07 | ✅ Disponible | `manifest/ssr-recipe07-package.xml` | Création dynamique de channel Slack (deal room) + invitation owner/manager |
| 08 | ✅ Disponible | `manifest/ssr-recipe08-package.xml` | Résumé Case (OpenAI / fallback) → DM Slack à l'owner |
| 09 | 🔜 Bientôt | — | Agentforce Pipeline Monitor |
| 10 | ✅ Disponible | `manifest/ssr-recipe10-package.xml` | Qualification IA + routage de lead (scoring OpenAI / fallback règles) → HOT / nurturing / disqualification + notification Slack ou e-mail |

Déployer les recettes **dans l'ordre** : la recette 01 inclut le socle ; chaque recette suivante ajoute son Flow et son enregistrement CMDT.

## Architecture (socle)

```
Flow → SlackInvocable → SlackCalloutQueueable → SlackService → Slack API
```

Le routing des channels se fait via `SSR_Slack_Recipe__mdt` (`recipe_01`, `recipe_02`, …).

## Sécurité

- Ne jamais commiter de vrais tokens Slack
- Les tokens se configurent dans `SSR_Slack_Settings__c` après déploiement
- Les Channel IDs dans les CMDT sont des placeholders à personnaliser

## Licence

MIT — voir [LICENSE](LICENSE).
