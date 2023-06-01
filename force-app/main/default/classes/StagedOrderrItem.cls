public with sharing class StagedOrderrItem extends StagedRecord {
    public Id SBQQ_UpgradedAsset__c {
        get {
            return (Id) this.get('SBQQ__UpgradedAsset__c');
        }
    }
    public Id SBQQ__BundleRoot__c {
        get {
            return this.get('SBQQ__BundleRoot__c');
        }
    }
}