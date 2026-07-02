# Salesforce Slack Recipes (SSR Stack)

Pack déployable d'intégration **Salesforce ↔ Slack** via Bot API : Flows, Apex, Custom Metadata et recettes incrémentales (01–09).

## Prérequis

- Org Salesforce (Developer, Sandbox ou Production) avec Apex et Flow
- [Salesforce CLI](https://developer.salesforce.com/tools/sfdxcli) (`sf`)
- Slack App avec Bot Token (`xoxb-...`) et scopes adaptés à chaque recette

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

## Recettes

| # | Manifest | Description |
|---|----------|-------------|
| 01 | `manifest/ssr-recipe01-package.xml` | Socle Apex + alerte nouvelle opportunité |
| 02 | `manifest/ssr-recipe02-package.xml` | Changement de stage |
| 03 | `manifest/ssr-recipe03-package.xml` | Escalade support |
| 04 | `manifest/ssr-recipe04-package.xml` | Closed Won manager |
| 05 | `manifest/ssr-recipe05-package.xml` | Approbation devis |
| 06 | `manifest/ssr-recipe06-package.xml` | Commande expédiée |
| 07 | `manifest/ssr-recipe07-package.xml` | Création de channel Slack |
| 08 | `manifest/ssr-recipe08-package.xml` | Résumé Case via OpenAI |
| 09 | `manifest/ssr-recipe09-package.xml` | Agentforce Pipeline Monitor |

Déployer les recettes **dans l'ordre** : chaque manifest inclut les dépendances de la recette concernée.

## Architecture (socle)

```
Flow → SlackInvocable → SlackCalloutQueueable → SlackService → Slack API
```

Le routing des channels se fait via `SSR_Slack_Recipe__mdt` (`recipe_01` … `recipe_09`).

## Sécurité

- Ne jamais commiter de vrais tokens Slack ou clés OpenAI
- Les tokens se configurent dans `SSR_Slack_Settings__c` après déploiement
- Les Channel IDs dans les CMDT sont des placeholders à personnaliser

## Licence

À définir (MIT recommandé pour un repo open source).
