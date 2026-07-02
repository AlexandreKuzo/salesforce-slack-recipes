# Salesforce Slack Recipes (SSR Stack)

Pack déployable d'intégration **Salesforce ↔ Slack** via Bot API : Flows, Apex, Custom Metadata et recettes incrémentales.

> **État actuel :** recettes **01** et **02** disponibles. Les recettes 03 à 09 arrivent progressivement — suivez le repo pour les releases.

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

## Recettes

| # | Statut | Manifest | Description |
|---|--------|----------|-------------|
| 01 | ✅ Disponible | `manifest/ssr-recipe01-package.xml` | Socle Apex + alerte nouvelle opportunité |
| 02 | ✅ Disponible | `manifest/ssr-recipe02-package.xml` | Alerte changement de stage |
| 03 | 🔜 Bientôt | — | Escalade support |
| 04 | 🔜 Bientôt | — | Closed Won manager |
| 05 | 🔜 Bientôt | — | Approbation devis |
| 06 | 🔜 Bientôt | — | Commande expédiée |
| 07 | 🔜 Bientôt | — | Création de channel Slack |
| 08 | 🔜 Bientôt | — | Résumé Case via OpenAI |
| 09 | 🔜 Bientôt | — | Agentforce Pipeline Monitor |

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
