// Demo data for SSR Recipe 10 — trois leads couvrant les trois tiers de routage.
// Exécuter APRÈS avoir activé le Flow "SSR Recipe 10 - Lead Qualification" :
// l'insertion déclenche le scoring async (OpenAI si clé configurée, sinon fallback règles).

List<Lead> leads = new List<Lead>{
    new Lead(
        FirstName = 'Nadia',
        LastName = 'Bernard',
        Company = 'Fintech Scale-up SAS',
        Industry = 'Finance',
        NumberOfEmployees = 450,
        Title = 'VP Engineering',
        Email = 'nadia.bernard@fintech.example',
        Country = 'France',
        LeadSource = 'Web',
        Status = 'Open - Not Contacted'
    ),
    new Lead(
        FirstName = 'Lea',
        LastName = 'Nguyen',
        Company = 'MidMarket Software Co',
        Industry = 'Technology',
        NumberOfEmployees = 40,
        Email = 'lea.nguyen@midmarket.example',
        LeadSource = 'Webinar',
        Status = 'Open - Not Contacted'
    ),
    new Lead(
        FirstName = 'Paul',
        LastName = 'Martin',
        Company = 'Boulangerie du coin',
        Industry = 'Retail',
        NumberOfEmployees = 3,
        LeadSource = 'Purchased List',
        Status = 'Open - Not Contacted'
    )
};

insert leads;

System.debug('=== SSR Recipe 10 DEMO LEADS ===');
for (Lead l : leads) {
    System.debug(
        l.Company + ' (' + l.Industry + ', ' + l.NumberOfEmployees + ' emp.) → ' +
        URL.getOrgDomainUrl().toExternalForm() + '/' + l.Id
    );
}
System.debug('Attendu : Fintech → HOT (Task 1h), MidMarket → NURTURE, Boulangerie → DISQUALIFIED.');
System.debug('Vérifier Score__c / AI_Reasoning__c / Confidence__c / Scored_At__c après ~10s (job async).');
