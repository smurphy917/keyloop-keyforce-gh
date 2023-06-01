public class QuoteLineItems {
    public List<SBQQ__QuoteLine__c> LineItems = new List<SBQQ__QuoteLine__c>();
    //public String approvalReason {get; set;}
    public ID quoteId {get; set;}
               
    public List<SBQQ__QuoteLine__c> getLineItems() {
        //Query quote line items
        LineItems = [
            SELECT  SBQQ__ProductCode__c, 
                    SBQQ__ProductName__c,
                    SBQQ__Quantity__c,
                    CurrencyIsoCode,
                    SBQQ__ListTotal__c,
                    SBQQ__NetTotal__c,
                    SBQQ__Discount__c,
                    RDApprovalRequired__c,
                    AftersalesReviewRequired__c,
                    Modified_Subscription_Term__c, 
                    SBQQ__EffectiveSubscriptionTerm__c, 
                    SBQQ__DefaultSubscriptionTerm__c, 
                    RPIAdjustmentCapAgreed__c,
                    Triggered_Approvals__c
            FROM    SBQQ__QuoteLine__c 
            WHERE   SBQQ__Quote__c =: quoteId                           
        ];
        
        
        /*List<SBQQ__QuoteLine__c> filteredItems = new List<SBQQ__QuoteLine__c>();
        //Filter line item records if approval reason provided
        if (approvalReason != '' && approvalReason != null){
            for (SBQQ__QuoteLine__c item : LineItems){
                if (item.Triggered_Approvals__c != null && item.Triggered_Approvals__c.contains(approvalReason)){
                    filteredItems.add(item);
                }
            }
            LineItems = filteredItems;
        }*/
        return LineItems;
    }
}