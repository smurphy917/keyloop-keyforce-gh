@isTest
public with sharing class JuventasTest {
    @TestSetup
    static void makeData(){
        Map<String, Map<String,Object>> overrides = new Map<String, Map<String,Object>>();
        Map<String,Object> accOverrides = new Map<String,Object>();
        Map<String,Object> acc01Overrides = new Map<String,Object>();
        Map<String,Object> acc02Overrides = new Map<String,Object>();
        accOverrides.put('Blocked__c','');
        acc01Overrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Company').getRecordTypeId());
        acc02Overrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Dealer').getRecordTypeId());
        acc02Overrides.put('Type','Dealership');

        overrides.put('Account',accOverrides);
        overrides.put('testDataAssetManagementAccount01', acc01Overrides);
        overrides.put('testDataAssetManagementAccount02', acc02Overrides);
        String[] objs = new String[]{
            'Pricebook2',
            'Product2',
            'PricebookEntry',
            'Legal_Entity__c',
            'Account',
            'Asset',
            'AssetStatePeriod'
        };
        TestUtility.loadData('testDataAssetManagement', objs, overrides);
    }
    @isTest
    public static void test() {
        // SELECT AssetId, Asset.LifecycleEndDate, Asset.Aggregate_Asset__r.AccountId, Asset.Aggregate_Asset__r.RootAssetId, Asset.Aggregate_Asset__r.RootAsset.LifecycleEndDate, StartDate, EndDate, Quantity, Asset.Co_Terminus__c, Asset.Product2.Renewal_Term__c FROM AssetStatePeriod WHERE Asset.Status = 'Installed' AND Asset.Aggregate_Asset__c != null AND Asset.ParentId != null AND  AssetId NOT IN (SELECT Asset__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Renewal__c = true) AND EndDate > 2024-07-01T00:00:00Z AND Asset.Aggregate_Asset__r.Account.RecordType.DeveloperName = 'Company' ORDER BY Asset.Aggregate_Asset__r.AccountId, Asset.Aggregate_Asset__r.RootAssetId, AssetId, Asset.LifecycleEndDate, EndDate
        List<AssetStatePeriod> asps = [SELECT Id FROM AssetStatePeriod WHERE Asset.Aggregate_Asset__r.Account.RecordType.DeveloperName = 'Company'];
        System.assertNotEquals(0, asps.size());
        Test.startTest();
        Juventas.BatchConfig cfg = new Juventas.BatchConfig(null,'Asset.Aggregate_Asset__r.Account.RecordType.DeveloperName = \'Company\'');
        cfg.concurrentBatches = 1;
        Database.executeBatch(new ImmortaliseBatchable(
            Date.newInstance(2024, 07, 01),
            cfg
        ), asps.size());
        Test.stopTest();
    }
}