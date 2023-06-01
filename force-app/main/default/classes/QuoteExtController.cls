public with sharing class QuoteExtController {
	private Id quoteId;
	private SBQQ__Quote__c quote;
	
	public QuoteExtController(ApexPages.StandardController stdController) {
		quoteId = stdController.getId();      
		quote = (SBQQ__Quote__c)stdController.getRecord();
	}
	public PageReference onSubmit() {        
		if (quoteId != null) {
            try {
        		SBAA.ApprovalAPI.submit(quoteId, SBAA__Approval__c.Quote__c);            
            } catch (DMLException e) {                        		
        		displayMessage(e);
                return null;
            }
		}
		return new PageReference('/' + quoteId);
	}
	public PageReference onRecall() {
		if (quoteId != null) {
            try {
	            SBAA.ApprovalAPI.recall(quoteId, SBAA__Approval__c.Quote__c);			                
            } catch (DMLException e) {
                displayMessage(e);
                return null;
            }            
		}
        incrementQuoteRevision(quote);
		return new PageReference('/' + quoteId);
    }
    
    void displayMessage(Exception e){
        Apexpages.addmessage(new Apexpages.Message(ApexPages.Severity.Error,e.getDmlMessage(0)));                
    }
    
	@TestVisible private void incrementQuoteRevision(SBQQ__Quote__c quote) {
		if (quote.Quote_Revision__c != null) {
			quote.Quote_Revision__c++;
			upsert quote;
		}
	}
}