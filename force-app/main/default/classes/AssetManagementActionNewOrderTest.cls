@isTest
public with sharing class AssetManagementActionNewOrderTest {
    static Id testOrderId;
    @TestSetup
    static void makeData(){
        Map<String,Map<String,Object>> overrides = new Map<String,Map<String,Object>>();
        Map<String,Object> orderOverrides = new Map<String,Object>();
        orderOverrides.put('EffectiveDate', Date.today());
        overrides.put('Order', orderOverrides);
        Map<String,Object> orderItemOverrides = new Map<String,Object>();
        orderItemOverrides.put('ServiceDate', Date.today());
        overrides.put('OrderItem', orderItemOverrides);
        Map<String,Object> acc01Overrides = new Map<String,Object>();
        acc01Overrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Company').getRecordTypeId());
        acc01Overrides.put('Blocked__c','');
        // acc01Overrides.put('Credit_Limit_Override__c',true);
        // acc01Overrides.put('Default_Payment_Method_one_time__c','BANK');
        // acc01Overrides.put('Default_Payment_Method_recurring__c','BANK');
        // acc01Overrides.put('Default_Payment_Terms_one_time__c','30DAYS');
        // acc01Overrides.put('Default_Payment_Terms_recurring__c','30DAYS');
        Map<String,Object> acc02Overrides = new Map<String,Object>();
        acc02Overrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Dealer').getRecordTypeId());
        acc02Overrides.put('Blocked__c','');
        // acc02Overrides.put('Credit_Limit_Override__c',true);
        // acc02Overrides.put('Default_Payment_Method_one_time__c','BANK');
        // acc02Overrides.put('Default_Payment_Method_recurring__c','BANK');
        // acc02Overrides.put('Default_Payment_Terms_one_time__c','30DAYS');
        // acc02Overrides.put('Default_Payment_Terms_recurring__c','30DAYS');
        overrides.put('testDataAssetManagementAccount01', acc01Overrides);
        overrides.put('testDataAssetManagementAccount02', acc02Overrides);
        TestUtility.loadData(
            'testDataAssetManagement',
            new String[]{
                // 'CustomNotificationType',
                'Pricebook2',
                'Product2',
                'PricebookEntry',
                'Legal_Entity__c',
                'Account',
                'Opportunity',
                'SBQQ__Quote__c',
                'Order',
                'OrderItem'
            },
            overrides
        );
    }
    @isTest
    static void test(){
        // Database.setSavepoint();
        TranquilityMock mockService = new TranquilityMock();
        Test.setMock(HttpCalloutMock.class, mockService);
        AssetManagementProcessTask.skipDML = true;
        Order o = [SELECT Id FROM Order LIMIT 1];
        List<OrderItem> ois = [SELECT Id FROM OrderItem WHERE OrderId = :o.Id];
        System.assertEquals(3, ois.size());
        AssetManagementActionNewOrder.InvocableParameter param = new AssetManagementActionNewOrder.InvocableParameter();
        param.orderId = o.Id;
        param.namedCredential = 'Salesforce';
        // Adding dependency to trigger test execution on deployment
        Serenity.namedCredential = 'Salesforce';
        Test.startTest();
        List<AssetManagementActionNewOrder.InvocableResult> results = AssetManagementActionNewOrder.InvocableGenerateAssets(new AssetManagementActionNewOrder.InvocableParameter[]{param});
        Test.stopTest();
        System.debug(StagedDatabase.toJSON());
        System.assertEquals(6, mockService.insertedIds.size());
    }
    /*
    @isTest
    static void batch(){
        AssetManagementProcessTask.skipDML = true;
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        Order o = [SELECT Id FROM Order LIMIT 1];
        List<OrderItem> ois = [SELECT Id FROM OrderItem WHERE OrderId = :o.Id];
        System.assertEquals(ois.size(),3);
        AssetManagementActionNewOrder.InvocableParameter param = new AssetManagementActionNewOrder.InvocableParameter();
        param.orderId = o.Id;
        param.namedCredential = 'Salesforce';
        Test.startTest();
        Serenity.USE_BATCH = true;
        List<AssetManagementActionNewOrder.InvocableResult> results = AssetManagementActionNewOrder.InvocableGenerateAssets(new AssetManagementActionNewOrder.InvocableParameter[]{param});
        List<AssetManagementProcessTask> queue = Serenity.queue;
        System.debug('Processing queue:\n' + JSON.serialize(queue));
        Database.executeBatch(new BatchableProcessAssetManagementTasks(queue, StagedDatabase.getState(), o.Id, 'Order Activation'),queue.size());
        Test.stopTest();
        List<StagedRecord> touched = new List<StagedRecord>();
        for (StagedRecord record : StagedDatabase.all()) {
            if(record.stagedFor != StagedRecord.StagedAction.NoAction) {
                touched.add(record);
            }
        }
        System.assertEquals(6, touched.size());
    }
    */
    @isTest
    static void processTaskTest() {
        // TODO: move to AssetManagementProcessTaskTest.cls
        AssetManagementProcessTask.skipDML = false;
        AssetManagementProcessTask task = new AssetManagementProcessTask(PWUtils.DMLOperation.DML_INSERT, new Product2(Name='Test Product', ProductCode='APX999', IsActive=true, SBQQ__SubscriptionPricing__c ='Fixed', SBQQ__SubscriptionTerm__c = 12));
        System.assertEquals(task.records.size(), 1);
        task.process();
        Product2 p = [SELECT Id FROM Product2 WHERE ProductCode = 'APX999' LIMIT 1];
        System.assertNotEquals(p, null);
    }

    public class AssetManagementTestException extends Exception{}
}