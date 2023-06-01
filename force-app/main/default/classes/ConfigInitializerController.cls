public with sharing class ConfigInitializerController {
    public Product2[] products {get; set;}
    public Boolean skip {get; set;}
    public ConfigInitializerController() {
        this.skip = false;
        System.debug('PAGE PARAMS');
        // System.debug(ApexPages.currentPage().getParameters());
        System.debug(JSON.serialize(ApexPages.currentPage().getParameters()));
        // Quote Id
        String qId = ApexPages.currentPage().getParameters().get('qid');
        SBQQ__Quote__c quote = [SELECT Id, SBQQ__Account__c FROM SBQQ__Quote__c WHERE Id = :qId];
        // String whereClause = new CPQProductSearch().getAdditionalSearchFilters(quote, new Map<String,Object>());
        // Quote Process Id
        // String qpId = ApexPages.currentPage().getParameters().get('qpid');
        // System.debug('QUOTE ID: ' + qId);
        // System.debug(JSON.serialize(ApexPages.currentPage().getParameters().keySet()));
        // comma-delimited product ids (generally only configuring one)
        String pidsStr = ApexPages.currentPage().getParameters().get('pids');
        String[] pids = pidsStr.split(',');
        this.products = [
            SELECT Id, ProductCode, (
                SELECT Id,
                SBQQ__Quantity__c,
                SBQQ__Selected__c,
                SBQQ__OptionalSKU__r.ProductCode,
                SBQQ__Feature__r.Name,
                SBQQ__QuoteLineVisibility__c,
                SBQQ__ProductCode__c
                FROM SBQQ__Options__r
            )
            FROM Product2
            WHERE Id IN :pids
        ];
        // List<Integer> remIdxs = new List<Integer>();
        if(ApexPages.currentPage().getParameters().get('Include Consultancy') != 'Yes') {
            // for (SBQQ__ProductOption__c opt : products[0].SBQQ__Options__r) {
            for (Integer idx = 0; idx < products[0].SBQQ__Options__r.size(); idx++) {
                SBQQ__ProductOption__c opt = products[0].SBQQ__Options__r[idx];
                if(opt.SBQQ__Feature__r.Name == 'One Time Fee') {
                    // remIdxs.add(idx);
                    opt.SBQQ__QuoteLineVisibility__c = 'Option Hidden';
                }
            }
        }
        for (SBQQ__ProductOption__c opt : products[0].SBQQ__Options__r) {
            if(opt.SBQQ__ProductCode__c == '10009477') {
                opt.SBQQ__Quantity__c = 4.0;
                opt.SBQQ__Selected__c = true;
            }
        }
        /*
        for (Integer remIdxIdx = remIdxs.size() -1; remIdxIdx >= 0; remIdxIdx--) {
            products[0].SBQQ__Options__r.remove(remIdxs[remIdxIdx]);
        }
        */
        // this.products = (List<Product2>) Database.query(
        //     'SELECT Id, ProductCode, (' + 
        //         'SELECT Id, SBQQ__Quantity__c, SBQQ__Selected__c, SBQQ__OptionalSKU__r.ProductCode FROM SBQQ__Options__r WHERE ' + whereClause.replace('Product2Id', 'SBQQ__OptionalSKU__c') + 
        //     ') ' + 
        //     'FROM Product2 WHERE Id IN (\'' + String.join(pids, '\',\'') + '\')'
        // );
        // this.products = [SELECT Id, ProductCode, (SELECT Id, SBQQ__Quantity__c, SBQQ__Selected__c, SBQQ__OptionalSKU__r.ProductCode FROM SBQQ__Options__r) FROM Product2 WHERE Id IN :pids];
        // for (SBQQ__ProductOption__c opt : this.products[0].SBQQ__Options__r) {
        //     if(opt.SBQQ__OptionalSKU__r.ProductCode == 'RULE_ITEM'){
        //         opt.SBQQ__Selected__c = true;
        //     }
        // }

    }
}