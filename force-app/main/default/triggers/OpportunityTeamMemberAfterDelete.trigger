trigger OpportunityTeamMemberAfterDelete on OpportunityTeamMember (after delete) {
    for (OpportunityTeamMember otm : Trigger.old) {
        Map<String,String> flowInputs = new Map<String,String>();
        flowInputs.put('recordId', otm.OpportunityId);
        Flow.Interview.createInterview('Replicate_Opportunity_Sharing_to_Quotes', flowInputs).start();
    }
}