trigger AccountTeamMemberAfterDelete on AccountTeamMember (after delete) {
    for (AccountTeamMember atm : Trigger.old) {
        List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE AccountId = :atm.AccountId];
        for (Opportunity opp : opps) {
            Map<String,String> flowInputs = new Map<String,String>();
            flowInputs.put('recordId', opp.Id);
            Flow.Interview.createInterview('Replicate_Opportunity_Sharing_to_Quotes', flowInputs).start();
        }
    }
}