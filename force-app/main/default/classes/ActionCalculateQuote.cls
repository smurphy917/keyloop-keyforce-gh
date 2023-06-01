public with sharing class ActionCalculateQuote implements Queueable, Database.AllowsCallouts {
    public Id quoteId;
    public ActionCalculateQuote(Id quoteId) {
        this.quoteId = quoteId;
    }
    public class InvocableParameter {
        @InvocableVariable(label='Quote Id')
        public Id quoteId;
    }
    @InvocableMethod(label='Calculate Quote')
    public static void calculateQuote(List<InvocableParameter> params) {
        for (InvocableParameter p : params) {
            // CPQ_QuoteCalculator.calculateAndSave(p.quoteId);
            // System.enqueueJob(new ActionCalculateQuote(p.quoteId));
            update [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :p.quoteId];
        }
    }
    public void execute(QueueableContext ctx) {
        update [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :this.quoteId];
    }
}