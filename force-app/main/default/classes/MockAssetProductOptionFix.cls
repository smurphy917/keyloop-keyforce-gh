public with sharing class MockAssetProductOptionFix {
    public MockAssetProductOptionFix() {

    }
    public static void run() {
        BatchQuery bq = new BatchQuery();
        BatchUpdate bu = new BatchUpdate();
        Database.executeBatch(new BatchableQueryUpdate(
            'SELECT Id, Product2Id, RootAsset.Product2Id FROM Asset WHERE SBQQ__ProductOption__c = null',
            bq,
            bu
        ),5000);
    }
    public class BatchQuery implements BatchableQueryUpdate.BatchQuery {
        public Map<Id,SBQQ__ProductOption__c> execute(List<Asset> batchRecords) {
            Map<Id,SBQQ__ProductOption__c> result = new Map<Id,SBQQ__ProductOption__c>();
            List<Id> prodIds = new List<Id>();
            Map<Id,List<Asset>> prodToAssets = new Map<Id,List<Asset>>();
            for (Asset a : batchRecords) {
                prodIds.add(a.Product2Id);
                List<Asset> prodAssets = prodToAssets.get(a.Product2Id);
                if(prodAssets == null) {
                    prodAssets = new List<Asset>();
                    prodToAssets.put(a.Product2Id, prodAssets);
                }
                prodAssets.add(a);
            }
            List<SBQQ__ProductOption__c> opts = [
                SELECT Id, SBQQ__Feature__c, SBQQ__OptionalSKU__c, SBQQ__ConfiguredSKU__c
                FROM SBQQ__ProductOption__c
                WHERE SBQQ__OptionalSKU__c IN :prodIds
            ];
            for (SBQQ__ProductOption__c opt : opts) {
                List<Asset> prodAssets = prodToAssets.get(opt.SBQQ__OptionalSKU__c);
                if (prodAssets.size() == 1) {
                    result.put(prodAssets[0].Id, opt);
                } else {
                    for (Asset a : prodAssets) {
                        if(a.RootAsset.Product2Id == opt.SBQQ__ConfiguredSKU__c) {
                            result.put(a.Id, opt);
                        }
                    }
                }
            }
            return result;
        }
    }
    public class BatchUpdate implements BatchableQueryUpdate.BatchUpdate {
        public void execute(List<SObject> batchRecords, Map<Id,SObject> sourceRecords) {
            for (Asset a : (List<Asset>) batchRecords) {
                SBQQ__ProductOption__c opt = (SBQQ__ProductOption__c) sourceRecords.get(a.Id);
                if(opt == null) {
                    continue;
                }
                a.SBQQ__ProductOption__c = opt.Id;
                a.SBQQ__DynamicOptionId__c = opt.SBQQ__Feature__c;
            }
        }
    }
}