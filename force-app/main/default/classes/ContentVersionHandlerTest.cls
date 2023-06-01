@isTest
public with sharing class ContentVersionHandlerTest {
    @TestSetup
    static void makeData(){
        Map<String,Map<String,Object>> overrides = new Map<String,Map<String,Object>>();
        Map<String,Object> accOverrides = new Map<String,Object>();
        accOverrides.put('Blocked__c','');
        overrides.put('Account', accOverrides);
        TestUtility.loadData('testDataAssetManagement', new String[]{
            'Legal_Entity__c',
            'Account',
            'Opportunity',
            'SBQQ__Quote__c'
        }, overrides);
    }
    @isTest
    public static void test(){
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        ContentVersion cv = new ContentVersion(
            Title='Test Document',
            PathOnClient='/',
            VersionData=Blob.valueOf('Test data')
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        System.assertNotEquals(null, cv.ContentDocumentId);
        insert new ContentDocumentLink(
            LinkedEntityId = quote.Id,
            ContentDocumentId = cv.ContentDocumentId
        );
        update cv;
    }
}