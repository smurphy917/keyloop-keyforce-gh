@isTest
public with sharing class ActionBatchUpdateTest {
    @TestSetup
    public static void makeData(){
        TestUtility.loadData('testDataAssetManagement', new String[]{,
            'Legal_Entity__c',
            'Account'
        });
        List<Contact> contacts = new List<Contact>();
        Account a = [SELECT Id FROM Account LIMIT 1];
        Integer count = 0;
        while(count < 10) {
            count++;
            contacts.add(
                new Contact(
                    AccountId=a.Id,
                    FirstName='Test-' + count,
                    LastName='User'
                )
            );
        }
        insert contacts;
    }
    @isTest
    public static void test(){
        List<Contact> contacts = [SELECT Id FROM Contact];
        for (Contact c : contacts) {
            c.LastName = 'UpdatedName';
        }
        ActionBatchUpdate.InvocableParameter p = new ActionBatchUpdate.InvocableParameter();
        p.records = contacts;
        p.batchSize = 10;
        ActionBatchUpdate.InvocableBatchUpdate(new ActionBatchUpdate.InvocableParameter[]{p});
    }
}