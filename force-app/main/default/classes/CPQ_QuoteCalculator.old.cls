public with sharing class CPQ_QuoteCalculator {
    public static void calculate(QuoteModel quote, String callbackClass) {
        QuoteCalculatorContext ctx = new QuoteCalculatorContext(quote, callbackClass);
        SBQQ.ServiceRouter.load('SBQQ.QuoteAPI.QuoteCalculator', null, JSON.serialize(ctx));    
    }
    public static void calculateAndSave(QuoteModel quote) {
        QuoteCalculatorContext ctx = new QuoteCalculatorContext(quote, 'CPQ_QuoteSaver');
        Id quoteId = quote.record.Id;
        SBQQ.ServiceRouter.load('SBQQ.QuoteAPI.QuoteCalculator', quoteId, JSON.serialize(ctx));
    }    
    
    private class QuoteCalculatorContext {        
        private QuoteModel quote;             //The quote and callbackClass properties are called in the API code by the exact names seen here.
        private String callbackClass;         //Altering these property names will cause calculator API calls to fail.

        private QuoteCalculatorContext(QuoteModel quote, String callbackClass) {
            this.quote = quote;            
            this.callbackClass = callbackClass;        
        }
    }
}