@isTest
public with sharing class JanusTest {
    @TestSetup
    static void makeData(){
        Map<String,Map<String,Object>> overrides = new Map<String,Map<String,Object>>();
        Map<String,Object> prod01Overrides = new Map<String,Object>();
        prod01Overrides.put('SBQQ__SubscriptionTerm__c',12);
        overrides.put('testDataAssetManagementProduct201', prod01Overrides);
        TestUtility.loadData(
            'testDataAssetManagement', 
            new String[]{
                'Legal_Entity__c',
                'Account',
                'Product2',
                'Asset_Migration_Record__c'
            },
            overrides
        );
    }
    @isTest
    public static void test() {
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        Test.startTest();
        AssetManagementProcessTask.skipDML = true;
        Janus.reign(
            new Janus.BatchConfig(
                5, // Blocks per batch
                null, // Total blocks per customer (limit)
                null, // Total customers
                2, // concurrent batches,
                null // Serenity.BatchConfig
            )
        );
        System.debug('TASKS: ' + JSON.serialize(Serenity.queue));
        Test.stopTest();
        List<Asset_Migration_Record__c> errors = [
            SELECT Id
            FROM Asset_Migration_Record__c
            WHERE Has_Error__c = true
        ];
        List<Asset_Migration_Record__c> successes = [
            SELECT Id
            FROM Asset_Migration_Record__c
            WHERE Asset__c != null
        ];
        System.assertEquals(0, errors.size());
        // System.assertNotEquals(0, successes.size());
        // System.assertEquals(4, successes.size());
    }
    @isTest
    public static void testSync() {
        TranquilityMock mockService = new TranquilityMock();
        Test.setMock(HttpCalloutMock.class, mockService);
        List<AggregateResult> rows = [SELECT Customer__c FROM Asset_Migration_Record__c GROUP BY Customer__c];
        List<Id> customerIds = new List<Id>();
        for (AggregateResult row : rows) {
            customerIds.add((Id) row.get('Customer__c'));
        }
        Test.startTest();
        AssetManagementProcessTask.skipDML = true;
        //System.enqueueJob(new JanusQueueable(customerIds));
        // Test.enqueueBatchJobs(10);
        Database.executeBatch(new ReignBatchable(
            new Janus.BatchConfig(
                5, // Blocks per batch
                null, // Total blocks per customer (limit)
                null, // Total customers (limit)
                1, // concurrent batches,
                null // Serenity.BatchConfig
            )),
            2
        );
        Test.stopTest();
        System.debug('INSERTED:');
        System.debug(mockService.insertedIds);
        System.debug('UPDATED:');
        System.debug(mockService.updatedIds);
        System.debug('SERIAL NUMBERS: ' + [SELECT Id FROM SerialNumber__c].size());
    }
}