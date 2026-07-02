/**
 * Slack channel provisioning for SSR Recipe 07 (conversations.create / invite / welcome).
 */
public with sharing class SlackChannelService {
    public class ChannelResult {
        public Boolean success;
        public String channelId;
        public String channelName;
        public String errorMessage;

        public ChannelResult(Boolean success, String channelId, String channelName, String errorMessage) {
            this.success = success;
            this.channelId = channelId;
            this.channelName = channelName;
            this.errorMessage = errorMessage;
        }
    }

    public static String buildDealChannelName(String accountName) {
        String slug = String.isBlank(accountName) ? 'client' : accountName.toLowerCase();
        slug = slug.replaceAll('[^a-z0-9]+', '-').replaceAll('^-+|-+$', '');
        if (String.isBlank(slug)) {
            slug = 'client';
        }
        if (slug.length() > 55) {
            slug = slug.substring(0, 55);
        }
        String name = 'deal-' + slug + '-' + String.valueOf(Date.today().year());
        return name.length() > 80 ? name.substring(0, 80) : name;
    }

    public static ChannelResult createChannel(String channelName) {
        if (String.isBlank(channelName)) {
            return new ChannelResult(false, null, null, 'Channel name is required.');
        }

        try {
            HttpResponse response = SlackService.sendSlackPost(
                '/conversations.create',
                new Map<String, Object>{
                    'name' => channelName.trim(),
                    'is_private' => false
                }
            );
            Map<String, Object> payload = SlackService.parseSlackJson(response);
            Boolean ok = payload.containsKey('ok') && (Boolean) payload.get('ok');

            if (ok) {
                Map<String, Object> channel = (Map<String, Object>) payload.get('channel');
                String channelId = channel != null ? (String) channel.get('id') : null;
                return new ChannelResult(true, channelId, channelName, null);
            }

            String error = (String) payload.get('error');
            return new ChannelResult(false, null, channelName, 'Slack API error: ' + error);
        } catch (Exception ex) {
            return new ChannelResult(false, null, channelName, ex.getMessage());
        }
    }

    public static String lookupUserByEmail(String email) {
        if (String.isBlank(email)) {
            return null;
        }

        try {
            String encodedEmail = EncodingUtil.urlEncode(email.trim(), 'UTF-8');
            HttpResponse response = SlackService.sendSlackGet('/users.lookupByEmail?email=' + encodedEmail);
            Map<String, Object> payload = SlackService.parseSlackJson(response);
            Boolean ok = payload.containsKey('ok') && (Boolean) payload.get('ok');

            if (!ok) {
                return null;
            }

            Map<String, Object> user = (Map<String, Object>) payload.get('user');
            return user != null ? (String) user.get('id') : null;
        } catch (Exception ex) {
            return null;
        }
    }

    public static Boolean inviteUsers(String channelId, List<String> slackUserIds) {
        if (String.isBlank(channelId) || slackUserIds == null || slackUserIds.isEmpty()) {
            return true;
        }

        Set<String> uniqueIds = new Set<String>();
        for (String userId : slackUserIds) {
            if (String.isNotBlank(userId)) {
                uniqueIds.add(userId.trim());
            }
        }
        if (uniqueIds.isEmpty()) {
            return true;
        }

        try {
            HttpResponse response = SlackService.sendSlackPost(
                '/conversations.invite',
                new Map<String, Object>{
                    'channel' => channelId,
                    'users' => String.join(new List<String>(uniqueIds), ',')
                }
            );
            Map<String, Object> payload = SlackService.parseSlackJson(response);
            return payload.containsKey('ok') && (Boolean) payload.get('ok');
        } catch (Exception ex) {
            return false;
        }
    }

    public static String buildWelcomeMessage(Opportunity opp) {
        String accountName = opp.Account != null ? opp.Account.Name : 'ce client';
        String ownerName = opp.Owner != null ? opp.Owner.Name : 'l\'équipe';
        return '🎉 *Nouveau deal room Slack*\n'
            + 'Channel dédié à *' + accountName + '* — opportunité *' + opp.Name + '*.\n'
            + 'Commercial : *' + ownerName + '*\n'
            + 'Montant : *' + opp.Amount + '€*';
    }
}
