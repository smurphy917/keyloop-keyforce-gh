@isTest
public class QuoteLineItemsTest {
    static Id quoteId='a00000000000000000';
    static QuoteLineItems ql = new QuoteLineItems();
    static List<SBQQ__QuoteLine__c> items = new List<SBQQ__QuoteLine__c>();

	@TestSetup
    static void makeData(){
        // Create test product
        Product2 testProd = new Product2(ProductCode='TESTPRD',Name='Test Product');
        insert testProd;
        
        // Create test quote
        SBQQ__Quote__c testQuote = new SBQQ__Quote__c(SBQQ__BillingCountry__c='Test Country');
        insert testQuote;
        
        // Add quote line to test quote        
		SBQQ__QuoteLine__c quoteLine = new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = testQuote.Id,
            SBQQ__Product__c = testProd.Id
        );
        insert quoteLine;
    }
    
    @isTest
    static void TestGetSet() {        
        ql.quoteId = quoteId;
    	System.assertEquals('a00000000000000000', ql.quoteId);
    }
    
    @isTest
    static void TestQueryWithResult() {
		List<SBQQ__Quote__c> quotes = [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__BillingCountry__c='Test Country' LIMIT 1];
        for (SBQQ__Quote__c q:quotes){
        	ql.quoteId = q.Id;    
        }        
        items = ql.getLineItems();
        System.assert(items.size()>0);       
    }
    
    @isTest
    static void TestQueryWithoutResult() {
    	ql.quoteId = null;
        items = ql.getLineItems();
        System.assert(items.size() == 0);
    }    
}