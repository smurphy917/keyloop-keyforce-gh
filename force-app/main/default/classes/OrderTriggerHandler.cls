public with sharing class OrderTriggerHandler {

   /************************** Routing Methods **************************/

    public static void afterInsert(List<Order> newList) {

        Set<Id> quoteIds = new Set<Id>();
        for (Order order : newList) {
            quoteIds.add(order.SBQQ__Quote__c);
        }

        if (!quoteIds.isEmpty()) {
            attachLatestContract(newList, quoteIds);
        }
    }

    /************************** Perform Business Logic **************************/

    public static void attachLatestContract(List<Order> newList, Set<Id> quoteIds) {

        Map<Id, SBQQ__Quote__c> quotesMap = new Map<Id, SBQQ__Quote__c>([
            SELECT Id,
                (
                    SELECT ContentDocumentId, ShareType, Visibility
                    FROM ContentDocumentLinks
                    ORDER BY SystemModstamp DESC
                    LIMIT 1
                )
            FROM SBQQ__Quote__c
        ]);

        List<ContentDocumentLink> cdlListToInsert = new List<ContentDocumentLink>();
        for (Order order : newList) {
            
            ContentDocumentLink originalCdl = quotesMap.get(order.SBQQ__Quote__c).ContentDocumentLinks.get(0);
            if (originalCdl == null) {
                continue;
            }

            ContentDocumentLink cdl = new ContentDocumentLink(
                LinkedEntityId = order.Id,
                ContentDocumentId = originalCdl.ContentDocumentId, 
                ShareType = originalCdl.ShareType, 
                Visibility = originalCdl.Visibility
            );

            cdlListToInsert.add(cdl);
        }

        insert cdlListToInsert;
    }

}