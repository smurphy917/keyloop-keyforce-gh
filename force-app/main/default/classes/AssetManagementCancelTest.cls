@isTest
public with sharing class AssetManagementCancelTest {
    @TestSetup
    static void makeData(){
        String[] objs = new String[]{
            // 'CustomNotificationType',
            'Pricebook2',
            'Product2',
            'PricebookEntry',
            'Legal_Entity__c',
            'Account',
            'Asset',
            'AssetStatePeriod',
            'AssetAction'
        };
        List<SObject> records = TestUtility.loadData('testDataAssetManagement', objs);
    }
    //@isTest
    //static void testCancel() {
    //    Test.setMock(HttpCalloutMock.class, new TranquilityMock());
    //    Asset a = [SELECT Id, AccountId FROM Asset LIMIT 1];
    //    AssetManagementActionCancel.InvocableParameter param = new AssetManagementActionCancel.InvocableParameter();
    //    param.accountId = a.AccountId;
    //    param.namedCredential = 'Salesforce';
    //    List<AssetManagementActionCancel.InvocableParameter> params = new List<AssetManagementActionCancel.InvocableParameter>{
    //        param
    //    };
    //    Test.startTest();
    //    AssetManagementActionCancel.InvocableDeleteAllAssetsForAccount(params);
    //    Test.stopTest();
    //    List<Asset> accountAssets = [SELECT Id FROM Asset WHERE AccountId = :a.AccountId AND Status != 'Cancelled' AND Id NOT IN (SELECT AssetId FROM AssetAction WHERE Type = 'Cancel')];
    //    System.assertEquals(0, accountAssets.size());
    //}
    @isTest
    static void testCancelBatch() {
        // AssetManagementProcessTask.skipDML = true;
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        Asset a = [SELECT Id, AccountId FROM Asset LIMIT 1];
        AssetManagementActionCancel.InvocableParameter param = new AssetManagementActionCancel.InvocableParameter();
        param.accountId = a.AccountId;
        param.namedCredential = 'Salesforce';
        List<AssetManagementActionCancel.InvocableParameter> params = new List<AssetManagementActionCancel.InvocableParameter>{
            param
        };
        Test.startTest();
        AssetManagementActionCancel.InvocableDeleteAllAssetsForAccount(params);
        Database.executeBatch(new BatchableProcessAssetManagementTasks(Serenity.queue, StagedDatabase.getState(), null, 'Manual', null), Serenity.queue.size());
        Test.stopTest();
        List<Asset> accountAssets = [SELECT Id FROM Asset WHERE AccountId = :a.AccountId AND Status != 'Cancelled' AND Id NOT IN (SELECT AssetId FROM AssetAction WHERE Type = 'Cancel')];
        System.assertEquals(0, accountAssets.size());
    }
    @isTest
    static void testCancelOne(){
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        Asset a = [SELECT Id, AccountId FROM Asset LIMIT 1];
        AssetManagementActionCancel.InvocableParameter param = new AssetManagementActionCancel.InvocableParameter();
        param.assetId = a.Id;
        param.namedCredential = 'Salesforce';
        Serenity.namedCredential = 'Salesforce'; // added to include dependency on Serenity (so this test is run when Serenity changes)
        List<AssetManagementActionCancel.InvocableParameter> params = new List<AssetManagementActionCancel.InvocableParameter>{
            param
        };
        Test.startTest();
        AssetManagementActionCancel.InvocableDeleteAllAssetsForAccount(params);
        Test.stopTest();
        List<Asset> assets = [SELECT Id FROM Asset WHERE Id = :a.Id AND Status != 'Cancelled' AND Id NOT IN (SELECT AssetId FROM AssetAction WHERE Type = 'Cancel')];
        System.assertEquals(0, assets.size());
    }
    @isTest
    static void testCancelTree(){
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        Asset a = [SELECT Id, AccountId FROM Asset LIMIT 1];
        AssetManagementActionCancel.InvocableParameter param = new AssetManagementActionCancel.InvocableParameter();
        Serenity.namedCredential = 'Salesforce'; // added to include dependency on Serenity (so this test is run when Serenity changes)
        param.assetId = a.Id;
        param.namedCredential = 'Salesforce';
        param.includeDescendants = true;
        List<AssetManagementActionCancel.InvocableParameter> params = new List<AssetManagementActionCancel.InvocableParameter>{
            param
        };
        Test.startTest();
        AssetManagementActionCancel.InvocableDeleteAllAssetsForAccount(params);
        Test.stopTest();
        List<Asset> assets = [SELECT Id FROM Asset WHERE Id = :a.Id AND Status != 'Cancelled' AND Id NOT IN (SELECT AssetId FROM AssetAction WHERE Type = 'Cancel')];
        System.assertEquals(0, assets.size());
    }
}