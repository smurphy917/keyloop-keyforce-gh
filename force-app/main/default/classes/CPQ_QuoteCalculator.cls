public with sharing class CPQ_QuoteCalculator implements SBQQ.CalculateCallback {
    public CPQ_QuoteCalculator(){}
    public void callback(String quoteJSON) {
        SBQQ.ServiceRouter.save('SBQQ.QuoteAPI.QuoteSaver', quoteJSON);
    }
    public static void calculateAndSave(Id quoteId) {
        // QuoteModel q = read(quoteId);
        // calculate(q, 'CPQ_QuoteCalculator');
        String quoteJSON = SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteCalculator', quoteId);
        (new CPQ_QuoteCalculator()).callback(quoteJSON);
    }
    public static void calculate(QuoteModel quote, String callbackClass) {
        QuoteCalculatorContext ctx = new QuoteCalculatorContext(quote, callbackClass);
        System.debug('QUOTE:\n'+ JSON.serialize(quote));
        SBQQ.ServiceRouter.load('SBQQ.QuoteAPI.QuoteCalculator', quote.record.Id, JSON.serialize(ctx));    
    }  
    public static QuoteModel read(String quoteId) {
        String quoteJSON = SBQQ.ServiceRouter.read('SBQQ.QuoteAPI.QuoteReader', quoteId);
        return (QuoteModel) JSON.deserialize(quoteJSON, QuoteModel.class);
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