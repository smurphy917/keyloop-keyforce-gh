public with sharing class ContentDocumentLinkTriggerHandler {
    
    /************************** Routing Methods **************************/
    public static void afterUpdate(List<ContentDocumentLink> newList) {

        System.debug('******Inside the trigger handler!!!');
        Map<Id, Id> quoteIdToContentDocumentLinkId = new Map<Id, Id>();
        for (ContentDocumentLink cdl : newList) {
            if (String.valueOf(cdl.LinkedEntity.getSObjectType()) == 'SBQQ__Quote__c') {
                System.debug('******This is a Quote after insert!');
                quoteIdToContentDocumentLinkId.put(cdl.LinkedEntityId, cdl.Id);
            }
        }

        if (!quoteIdToContentDocumentLinkId.isEmpty()) {
            populatePrimaryContract(quoteIdToContentDocumentLinkId);
        }
    }

    /************************** Helper Methods **************************/
    public static void populatePrimaryContract(Map<Id, Id> quoteIdToContentDocumentLinkId) {

        List<SBQQ__Quote__c> quotesToUpdate = [
            SELECT Id
            FROM  SBQQ__Quote__c
            WHERE Id IN :quoteIdToContentDocumentLinkId.keySet()
        ];

        for (SBQQ__Quote__c quote : quotesToUpdate) {
            quote.Primary_Contract_Id__c = quoteIdToContentDocumentLinkId.get(quote.Id);
            System.debug('******Primary Contract field updated on the Quote' + quote);
        }

        update quotesToUpdate;
    }

}