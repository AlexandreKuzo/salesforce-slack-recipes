// Demo data for SSR Recipe 08 — rich Case + EmailMessages (IsEscalated left false)
Account acct = new Account(Name = 'Acme Corp');
insert acct;

Case c = new Case(
    AccountId = acct.Id,
    Subject = 'Impossible d\'accéder au portail client depuis la mise à jour v3.2',
    Description =
        'Le client signale que 5 utilisateurs de l\'équipe Finance ne peuvent plus se connecter ' +
        'au portail client depuis le déploiement de la v3.2 (mardi soir). ' +
        'Erreur affichée : "Access Denied — profile mismatch". ' +
        'Impact business : clôture mensuelle bloquée. Contact principal : Marie Dubois (Finance).',
    Priority = 'High',
    Status = 'Working',
    Origin = 'Email',
    Reason = 'Complex functionality',
    Type = 'Problem',
    IsEscalated = false
);
insert c;
c = [SELECT Id, CaseNumber FROM Case WHERE Id = :c.Id];

Datetime now = System.now();
String caseRef = c.CaseNumber;

List<EmailMessage> emails = new List<EmailMessage>{
    new EmailMessage(
        ParentId = c.Id,
        Status = '1',
        Incoming = true,
        FromAddress = 'marie.dubois@acme-corp.example',
        ToAddress = 'support@yourcompany.example',
        Subject = 'URGENT — Accès portail Finance KO après v3.2',
        MessageDate = now.addDays(-3),
        TextBody =
            'Bonjour,\n\n' +
            'Depuis la mise à jour v3.2 déployée mardi soir, 5 utilisateurs Finance ' +
            '(dont moi) reçoivent "Access Denied — profile mismatch" en tentant de ' +
            'se connecter au portail client.\n\n' +
            'Nous avions accès sans problème jusqu\'à lundi. La clôture mensuelle ' +
            'démarre vendredi — c\'est bloquant.\n\n' +
            'Pouvez-vous investiguer en priorité ?\n\n' +
            'Marie Dubois\nContrôleur Financier — Acme Corp'
    ),
    new EmailMessage(
        ParentId = c.Id,
        Status = '3',
        Incoming = false,
        FromAddress = 'support@yourcompany.example',
        ToAddress = 'marie.dubois@acme-corp.example',
        Subject = 'RE: URGENT — Accès portail Finance KO après v3.2',
        MessageDate = now.addDays(-2).addHours(-4),
        TextBody =
            'Bonjour Marie,\n\n' +
            'Merci pour le signalement. Nous avons créé le case #' + caseRef + '.\n\n' +
            'Actions déjà tentées de notre côté :\n' +
            '1. Réinitialisation du mot de passe (votre compte)\n' +
            '2. Vidage du cache navigateur / mode navigation privée\n' +
            '3. Test d\'accès via Chrome et Edge\n\n' +
            'Le problème semble lié aux profils post-déploiement v3.2. ' +
            'Nous vérifions les droits du profil "Portal Finance User".\n\n' +
            'On revient vers vous dès que possible.\n\n' +
            'Support Client'
    ),
    new EmailMessage(
        ParentId = c.Id,
        Status = '1',
        Incoming = true,
        FromAddress = 'marie.dubois@acme-corp.example',
        ToAddress = 'support@yourcompany.example',
        Subject = 'RE: URGENT — Accès portail Finance KO après v3.2',
        MessageDate = now.addDays(-2),
        TextBody =
            'Merci pour le retour.\n\n' +
            'J\'ai testé Chrome + Edge en navigation privée : même erreur. ' +
            'La réinit du mot de passe n\'a rien changé.\n\n' +
            'Autre élément : un collègue Sales (profil différent) accède encore ' +
            'au portail normalement. Ça pointe bien vers un souci de profil Finance.\n\n' +
            'Pouvez-vous escalader ? La clôture approche.\n\n' +
            'Marie'
    ),
    new EmailMessage(
        ParentId = c.Id,
        Status = '3',
        Incoming = false,
        FromAddress = 'support@yourcompany.example',
        ToAddress = 'marie.dubois@acme-corp.example',
        Subject = 'RE: URGENT — Accès portail Finance KO après v3.2',
        MessageDate = now.addDays(-1),
        TextBody =
            'Marie,\n\n' +
            'Update : l\'équipe plateforme a identifié un écart de permission set ' +
            'sur "Portal Finance User" après v3.2 (objet Invoice manquant en lecture).\n\n' +
            'Correction prévue demain matin. En attendant, nous préparons une ' +
            'permission set temporaire pour votre équipe.\n\n' +
            'Je vous tiens au courant.\n\n' +
            'Support Client — Niveau 1'
    ),
    new EmailMessage(
        ParentId = c.Id,
        Status = '1',
        Incoming = true,
        FromAddress = 'marie.dubois@acme-corp.example',
        ToAddress = 'support@yourcompany.example',
        CcAddress = 'cfo@acme-corp.example',
        Subject = 'RE: URGENT — Accès portail Finance KO après v3.2 — escalade demandée',
        MessageDate = now.addHours(-6),
        TextBody =
            'Bonjour,\n\n' +
            'Toujours pas d\'accès ce matin. Notre CFO est en copie : sans portail, ' +
            'impossible de valider les écritures de clôture.\n\n' +
            'Merci d\'escalader officiellement et de nous confirmer un créneau ' +
            'pour la permission set temporaire aujourd\'hui.\n\n' +
            'Marie Dubois'
    )
};

insert emails;

c = [SELECT Id, CaseNumber, Subject, Priority, Status, Owner.Email FROM Case WHERE Id = :c.Id];

System.debug('=== SSR Recipe 08 DEMO CASE ===');
System.debug('Case Id      : ' + c.Id);
System.debug('Case Number  : ' + c.CaseNumber);
System.debug('Subject      : ' + c.Subject);
System.debug('Owner Email  : ' + c.Owner.Email);
System.debug('Emails       : ' + emails.size());
System.debug('URL          : ' + URL.getOrgDomainUrl().toExternalForm() + '/' + c.Id);
System.debug('Next step    : set IsEscalated = true (or change Owner) after Flow is Active');
