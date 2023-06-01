@isTest
private class QuoteExtControllerTests {
    @testSetup static void setup() {
        Account testAcc = new Account();
		testAcc.Name = 'Test Acc';
		testAcc.Type = 'Company';
        testAcc.Blocked__c = null;
        insert testAcc;
        
        SBQQ__Quote__c draftQuote = new SBQQ__Quote__c();
        draftQuote.SBQQ__Status__c = 'Draft';
        draftQuote.SBQQ__Account__c = testAcc.Id;
        draftQuote.Reference__c = 'GB-00000-REVX';
        insert draftQuote; 
        
        SBQQ__Quote__c approvedQuote = new SBQQ__Quote__c();
        approvedQuote.SBQQ__Status__c = 'Approved';
        approvedQuote.SBQQ__Account__c = testAcc.Id;
        approvedQuote.Reference__c = 'GB-00001-REVX';
        insert approvedQuote;  
    }
    
    testMethod static void testSubmit() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c WHERE Reference__c='GB-00000-REVX' LIMIT 1];
        Test.startTest();
        QuoteExtController con = new QuoteExtController(new ApexPages.StandardController(quote));
        con.onSubmit();
        quote = [SELECT ApprovalStatus__c FROM SBQQ__Quote__c WHERE Id = :quote.Id LIMIT 1];
        Test.stopTest();
        
        System.assertEquals('Approved', quote.ApprovalStatus__c);
    }
    
    testMethod static void testSubmitFail() {
        Account acc = [SELECT Id, Blocked__c FROM Account WHERE Name = 'Test Acc' LIMIT 1];
        acc.Blocked__c = 'Blocked All';
        update acc;

        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c WHERE Reference__c='GB-00000-REVX' LIMIT 1];        
        Test.startTest();
        QuoteExtController con = new QuoteExtController(new ApexPages.StandardController(quote));
        con.onSubmit();
        Test.stopTest();
        
        System.assert(ApexPages.hasMessages(), 'There should be an error');
    }
    
    testMethod static void testRecall() {
        SBQQ__Quote__c quote = new SBQQ__Quote__c();
        insert quote;
        
        Test.startTest();
        QuoteExtController con = new QuoteExtController(new ApexPages.StandardController(quote));        
        con.onRecall();        
        quote = [SELECT ApprovalStatus__c, Quote_Revision__c FROM SBQQ__Quote__c WHERE Id = :quote.Id LIMIT 1];        
        
        Double quoteRevision = quote.Quote_Revision__c;
        con.incrementQuoteRevision(quote);        
        Test.stopTest();
        
        System.assertEquals('Recalled', quote.ApprovalStatus__c);
        System.assertEquals(quoteRevision+1, quote.Quote_Revision__c);
    }
    
    testMethod static void testRecallFail() {
        Account acc = [SELECT Id, Blocked__c FROM Account WHERE Name = 'Test Acc' LIMIT 1];
        acc.Blocked__c = 'Blocked All';
        update acc;
        
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c WHERE Reference__c='GB-00001-REVX' LIMIT 1];
        
        Test.startTest();
        QuoteExtController con = new QuoteExtController(new ApexPages.StandardController(quote));        
        con.onRecall(); 
        Test.stopTest();
        
        System.assert(ApexPages.hasMessages(), 'There should be an error');
    }
    
}