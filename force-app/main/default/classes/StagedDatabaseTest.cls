@isTest
public with sharing class StagedDatabaseTest {
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
        acc01Overrides.put('Blocked__c', '');
        Map<String,Object> acc02Overrides = new Map<String,Object>();
        acc02Overrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Dealer').getRecordTypeId());
        acc02Overrides.put('Blocked__c', '');
        overrides.put('testDataAssetManagementAccount01', acc01Overrides);
        overrides.put('testDataAssetManagementAccount02', acc02Overrides);
        TestUtility.loadData(
            'testDataAssetManagement',
            new String[]{
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
    static void addWhereTest(){
        Order o = [SELECT Id FROM Order LIMIT 1];
        StagedDatabase.addWhere(
            'OrderItem',
            'OrderId = \'' + o.Id + '\'',
            new String[]{}
        );
        System.debug(StagedDatabase.toJSON());
        System.assertNotEquals(0, StagedDatabase.all().size());
    }
}