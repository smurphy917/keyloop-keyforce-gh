public without sharing class ContentVersionHandler {
    public static void updateCustomerAcceptance(ContentVersion cv) {
        List<ContentDocumentLink> cdls = [SELECT LinkedEntityId FROM ContentDocumentLink WHERE ContentDocumentId = :cv.ContentDocumentId];
        List<Id> queryIds = new List<Id>();
        for (ContentDocumentLink cdl : cdls) {
            queryIds.add(cdl.LinkedEntityId);
        }
        List<SBQQ__Quote__c> quotes = [SELECT Id FROM SBQQ__Quote__c WHERE Id IN :queryIds];
        for (SBQQ__Quote__c q : quotes) {
            Map<String,String> flowInputs = new Map<String,String>();
            flowInputs.put('quoteId', q.Id);
            Flow.Interview.createInterview('Subflow_Set_Customer_Acceptance', flowInputs).start();
        }
    }
}