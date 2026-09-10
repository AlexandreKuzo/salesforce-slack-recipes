# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Salesforce DX source project ("SSR Stack") shipping **incremental, independently deployable recipes** for outbound Salesforce → Slack (and OpenAI) integration via the Slack Web API. No namespace, source API 65.0, single package dir `force-app/`. There is no LWC/Aura code yet — everything is Apex + Flow + metadata.

## Commands

```bash
# Deploy one recipe (deploy in numeric order — recipe 01 carries the shared base)
sf project deploy start --manifest manifest/ssr-recipe01-package.xml --target-org my-org

# Run all Apex tests / a single class / a single method
sf apex run test --target-org my-org --test-level RunLocalTests --result-format human --code-coverage
sf apex run test --target-org my-org --class-names SlackServiceTest --result-format human
sf apex run test --target-org my-org --tests SlackServiceTest.postMessage_success --result-format human

# Run an anonymous Apex script (demo data generators live in scripts/apex/)
sf apex run --target-org my-org --file scripts/apex/demo-recipe08-case.apex

# Formatting & lint (lint only matches aura/lwc — currently no-op until UI code exists)
npm run prettier          # write; prettier:verify to check
npm run lint
npm run test:unit         # sfdx-lwc-jest (no LWC yet)
```

Prettier runs on commit via husky + lint-staged. Apex is formatted with `prettier-plugin-apex`, XML with `@prettier/plugin-xml`.

## Architecture

Every recipe follows the same four-layer async pipeline:

```
Record-triggered Flow (RecordAfterSave)
  → *Invocable          @InvocableMethod, validates input, System.enqueueJob(...)
  → *Queueable          implements Queueable, Database.AllowsCallouts — runs callouts OUTSIDE the trigger txn
  → *Service            builds + sends the HTTP callout, parses the Slack/OpenAI response
  → Slack / OpenAI Web API
```

Callouts are **always** deferred to a Queueable because the entry points are record-triggered Flows (you cannot call out synchronously from a trigger). Invocables return immediately with `queued = true`. Every Queueable takes an `SSRLogger` and records each step to `SSR_Log__c` (see Observability below) — that, `AsyncApexJob`, and debug logs are where you look, not the Flow result.

**Inside the Queueable, every callout must run before the first DML statement** — once there is uncommitted work, a callout throws `System.CalloutException: You have uncommitted work pending`, which `SlackService.postMessage` swallows into `success = false` (silent). Recipe 07 and 10 both notify Slack *first*, then persist. Mocked callouts in unit tests do NOT enforce this rule, so this class of bug only shows up against a real org.

### Observability — `SSR_Log__c`

`SSRLogger(recipeKey, recordId).setJobId(context.getJobId())` — buffered: `.success/.warning/.error(step, message[, mode])` append rows; `.flush()` does one `insert` from the Queueable's `finally`. Logging never throws (a failed flush is swallowed). `SSRLogPurgeSchedulable` prunes rows older than `SSR_Slack_Settings__c.Log_Retention_Days__c` (default 30) — scheduled by the admin post-deploy.

### Service classes (four families, one shared HTTP core)

- **`SlackService`** — the HTTP core. `postMessage(channelId, text)` calls `chat.postMessage`; a Slack **user ID** works as the `channel` arg, which is how recipe 08 sends DMs. Also `lookupUserByEmail()` (`users.lookupByEmail` — used by recipes 07 and 08), the shared low-level helpers `sendSlackPost` / `sendSlackGet` / `parseSlackJson`, `appendRecordLink()` (adds a "Voir dans Salesforce" deep link), and `resolveChannelIdForRecipe()`.
- **`SlackChannelService`** (recipe 07) — `conversations.create`, `conversations.invite`, deal-room channel-name slugging.
- **`CaseSummaryService`** (recipe 08) — calls OpenAI `gpt-4o-mini` for a Case summary; **silently falls back** to `buildRuleBasedSummary()` when no API key is configured or the callout fails. `SummaryResult.mode` is `"openai"` or `"fallback"`.
- **`LeadScoringService`** (recipe 10) — same OpenAI-or-fallback pattern for lead scoring (`ScoreResult.mode`), plus `route()` (HOT / NURTURE / DISQUALIFIED from `SSR_Lead_Scoring_Config__mdt` thresholds), `buildSlackMessage()` and `sendEmailFallback()`. Fallback scoring reads `SSR_Lead_Industry_Score__mdt`. Same `@TestVisible` override fields as `CaseSummaryService`, plus `testConfigOverride`.

### Channel routing — Custom Metadata

Fixed-channel recipes (01, 02) resolve their target channel from `SSR_Slack_Recipe__mdt`, keyed by `Recipe_Key__c` (`recipe_01`, `recipe_02`, …), with `Channel_Id__c` + `Is_Active__c`. Records ship with placeholder channel id `C0123456789` — must be edited post-deploy. Recipes 07/08 do **not** use CMDT routing (07 creates a channel, 08 DMs the owner). Recipe 10 uses it indirectly: `resolveChannelIdForRecipe()` throwing (unconfigured/inactive key) is the signal to fall back to e-mail.

### Secrets & config — hierarchy Custom Setting

`SSR_Slack_Settings__c` (Protected hierarchy custom setting), read via `getOrgDefaults()`:
- `Bot_Token__c` — Slack bot token (`xoxb-…`), required
- `OpenAI_Api_Key__c` — optional (`sk-…`); absence triggers the recipe-08 fallback

Outbound hosts are allow-listed via `RemoteSiteSetting` (`SSR_Slack` → `slack.com`, `SSR_OpenAI` → `api.openai.com`). Note: some class doc-comments mention a "Named Credential" — that is stale; the implementation uses a Bearer token from the custom setting + remote site settings.

### Permission set

`SSR_Slack_User` grants Apex class access + custom-setting read, and sets `Opportunity.SlackChannelId__c` to **read-only** (populated only by the recipe-07 Apex, never by hand). Assign it to any user who triggers the Flows.

## Testing conventions

- HTTP is mocked with `Test.setMock(HttpCalloutMock.class, …)` using `SlackApiMock` (ok/error toggle), `SlackChannelApiMock`, `CaseSummaryApiMock` / `LeadQualificationApiMock` (route response by endpoint substring; instance flags like `lookupFound`, `slackOk`, `openAiStatus` for the failure paths).
- Config/callout dependencies are bypassed with `@TestVisible` static override fields: `SlackService.testBotTokenOverride`, `SlackService.testRecipesOverride` (stub `SSR_Slack_Recipe__mdt` so channel tests don't depend on deployed CMDT), `CaseSummaryService` / `LeadScoringService` `.testOpenAiApiKeyOverride` / `.testOpenAiResponseOverride` / `.forceNoOpenAiKeyInTest`, `LeadScoringService.testConfigOverride`.
- `parsePostMessageResponse` / `resolveChannelIdForRecipe` / `buildRuleBasedScore` and other internals are exposed `@TestVisible` for direct unit testing.
- Test classes that touch custom settings run `@IsTest(IsParallel=false)`.
- **`Case.Owner.*` does not resolve in test context** (polymorphic owner) — read the owner e-mail with a direct `User` query (see `CaseSummaryQueueable.ownerEmail()`), never `Case.Owner.Email`. `Opportunity.Owner.*` is a plain lookup and is fine.
- Any test doing DML then a callout in the same transaction hits the uncommitted-work rule with **real** mocks off but not with `Test.setMock` — do the DML before `Test.startTest()`.

## Deployment

Each `manifest/ssr-recipeNN-package.xml` is **self-contained**: it carries the whole SSR stack (all Apex, every custom object/field, `SSR_Slack_User`, both remote sites, `SSR_Log__c` + tab) plus that recipe's Flow / CMDT records / quick action. Deploy any recipe to a clean org in any order. Because every manifest ships every class, deploys need the full suite: `--test-level RunLocalTests` (org-wide 75%) or `RunSpecifiedTests` naming all seven test classes (per-class 75%).

## Conventions

- **Language split:** user-facing strings (Slack messages, Flow labels, permission-set descriptions, error messages surfaced to admins) are in **French**; Apex identifiers and code comments are in **English**.
- When adding a recipe: add the `*Invocable`/`*Queueable` classes (with an `SSRLogger`), the `.flow-meta.xml`, a `manifest/ssr-recipeNN-package.xml` (the shared base block + this recipe's Flow / CMDT / quick action — the base is identical across manifests), a CMDT record if it uses fixed-channel routing, wire the new classes/fields into `SSR_Slack_User` **and into every recipe manifest** (single perm set, so each manifest must carry all classes it references), and update the recipe table + deploy notes in `README.md`.
- `docs/slack-app-manifest.yaml` is the minimal Slack app manifest (recipe 01, `chat:write` only); recipes 07/08 need `channels:manage`, `channels:read`, `users:read.email` added.
