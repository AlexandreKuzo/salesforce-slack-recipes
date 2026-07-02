/**
 * Returns the daily kickoff prompt for the Pipeline Monitor Agent (Scheduled Flow).
 */
public with sharing class PipelineMonitorKickoffInvocable {
    public class Request {
        @InvocableVariable(
            label='Schedule Label'
            description='Optional label for the scheduled run (ex. Daily 8am). Can be left blank.'
        )
        public String scheduleLabel;
    }

    public class Response {
        @InvocableVariable(
            label='Agent Prompt'
            description='User message to pass to the Run Agent flow action.'
        )
        public String agentPrompt;
    }

    @InvocableMethod(
        label='SSR Pipeline Monitor Kickoff'
        description='Builds the daily surveillance prompt for the Pipeline Monitor Agent scheduled run.'
        category='SSR Slack Recipes'
    )
    public static List<Response> buildKickoffPrompt(List<Request> requests) {
        Response res = new Response();
        res.agentPrompt =
            'Exécute ta surveillance quotidienne du pipeline Salesforce.\n\n'
            + 'Détecte :\n'
            + '- Opportunités ouvertes sans activité depuis plus de 30 jours\n'
            + '- Deals en stage Negotiation dont la CloseDate est dépassée\n'
            + '- Comptes avec 3 cases ouverts ou plus\n\n'
            + 'Pour chaque situation détectée :\n'
            + '1. Rédige une alerte claire en français\n'
            + '2. Indique le risque business en 1 phrase\n'
            + '3. Propose une action concrète immédiate\n'
            + '4. Envoie via l\'action SSR Send Slack Notification (recipe_09, recordId si pertinent)\n\n'
            + 'Ne notifie que les situations réellement à risque — pas de spam.';

        return new List<Response>{ res };
    }
}
