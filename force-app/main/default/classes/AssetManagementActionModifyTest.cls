@isTest
public with sharing class AssetManagementActionModifyTest {
    @TestSetup
    static void makeData(){
        Map<String,Map<String,Object>> overrides = new Map<String,Map<String,Object>>();
        Map<String,Object> acc01Overrides = new Map<String,Object>();
        acc01Overrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Company').getRecordTypeId());
        acc01Overrides.put('Blocked__c', '');
        Map<String,Object> acc02Overrides = new Map<String,Object>();
        acc02Overrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Dealer').getRecordTypeId());
        acc02Overrides.put('Blocked__c', '');
        acc02Overrides.put('Type', 'Dealership');
        overrides.put('testDataAssetManagementAccount01', acc01Overrides);
        overrides.put('testDataAssetManagementAccount02', acc02Overrides);
        String[] objects = new String[]{
            'Product2',
            'Pricebook2',
            'PricebookEntry',
            'Legal_Entity__c',
            'Account',
            'Asset',
            'AssetAction',
            'AssetStatePeriod'
        };
        TestUtility.loadData('testDataAssetManagement',objects,overrides);
        System.assertNotEquals(0, [SELECT Id FROM Asset].size());
    }

    @isTest
    public static void test() {
        PWUtils.standardPricebookId = Test.getStandardPricebookId();
        Asset siteRoot = [SELECT Id, AccountId, LifecycleStartDate, LifecycleEndDate, Aggregate_Asset__c FROM Asset WHERE HasLifecycleManagement = true AND ParentId = null AND Aggregate_Asset__c != null LIMIT 1];
        Asset custRoot = [SELECT Id, AccountId, LifecycleStartDate, LifecycleEndDate FROM Asset WHERE HasLifecycleManagement = true AND ParentId = null AND Aggregate_Asset__c = null LIMIT 1];
        Datetime modifyDate = Datetime.valueOf((siteRoot.LifecycleStartDate.getTime() + siteRoot.LifecycleEndDate.getTime()) / 2);
        List<AssetStatePeriod> descASPs = [SELECT Id FROM AssetStatePeriod WHERE Asset.RootAssetId = :siteRoot.Id AND StartDate <= :modifyDate AND EndDate >= :modifyDate ];

        Opportunity o = new Opportunity(
            AccountId=custRoot.AccountId,
            Name='Apex Test Opp',
            StageName='Qualification',
            CloseDate=Date.today().addDays(1)
        );
        insert o;
        SBQQ__Quote__c q = new SBQQ__Quote__c(
            SBQQ__Opportunity2__c=o.Id, 
            SBQQ__Account__c=custRoot.AccountId
        );
        insert q;

        // New Opp & Quote
        AssetManagementActionModify.InvocableParameter param1 = new AssetManagementActionModify.InvocableParameter();
        // New Quote
        // AssetManagementActionModify.InvocableParameter param2 = new AssetManagementActionModify.InvocableParameter();
        // param2.opportunityId = o.Id;
        // Existing Quote
        // AssetManagementActionModify.InvocableParameter param3 = new AssetManagementActionModify.InvocableParameter();
        // param3.quoteId = q.Id;

        Test.startTest();
        for (AssetManagementActionModify.InvocableParameter param : new List<AssetManagementActionModify.InvocableParameter>{param1/*, param2, param3*/}) {
            param.assetId = custRoot.Id;
            param.requestDate = modifyDate;
            param.assetAccountIds = new String[]{siteRoot.AccountId};
            param.type = 'Amendment';
            param.oppSubType = 'Upsell';
            List<AssetManagementActionModify.InvocableResult> results = AssetManagementActionModify.InvocableModifyAsset(new AssetManagementActionModify.InvocableParameter[]{param});
            System.assertEquals(results.size(),1);
            List<SBQQ__QuoteLine__c> qls = [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :results[0].quoteId];
            System.assertEquals(qls.size(), descASPs.size());
        }
        Test.stopTest();
    }
    @isTest
    public static void renewalTest(){
        Asset a = [SELECT Id FROM Asset WHERE ParentId = null AND Aggregate_Asset__c = null LIMIT 1];
        Thrill.GenerateAndSave(a.Id, null, Thrill.TransactionType.Renewal, null, null, null);
    }
}