@isTest
public with sharing class QuoteAccessTest {
    @TestSetup
    static void makeData(){
        TestUtility.loadData(
            'testDataAssetManagement',
            new String[]{
                'Pricebook2',
                'Legal_Entity__c',
                'Account',
                'Opportunity',
                'SBQQ__Quote__c'
            }
        );
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User']; 
        User u = new User(
            ProfileId = p.Id,
            FirstName = 'Apex',
            LastName = 'Test',
            Username = 'test.apex.user@email.com',
            Email = 'bogus@email.com',
            Alias = 'bogus',
            TimeZoneSidKey = 'GMT',
            LocaleSidKey = 'en_GB',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8'
        );
        insert u;
        insert new OpportunityTeamMember(
            OpportunityId = [SELECT Id FROM Opportunity LIMIT 1].Id,
            UserId = u.Id,
            OpportunityAccessLevel = 'Read'
        );
        insert new AccountTeamMember(
            AccountId = [SELECT Id FROM Account LIMIT 1].Id,
            UserId = u.Id,
            AccountAccessLevel = 'Read'
        );
    }
    @isTest
    public static void testOppTeamDelete() {
        delete [SELECT Id FROM OpportunityTeamMember];
    }
    @isTest
    public static void testAcctTeamDelete() {
        delete [SELECT Id FROM AccountTeamMember];
    }
}