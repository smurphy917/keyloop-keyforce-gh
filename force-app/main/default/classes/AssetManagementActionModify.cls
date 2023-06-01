public without sharing class AssetManagementActionModify {
    public class InvocableParameter {
        @InvocableVariable(label='Id of Asset to be modified.' required=true)
        public String assetId;
        @InvocableVariable(label='Change type' description='Valid values are: "Renewal", "Amendment" or "Recontract"' required=true)
        public String type;
        @InvocableVariable(label='Id of Quote to be appended to')
        public String quoteId;
        @InvocableVariable(label='Id of Opportunity to add new quote to')
        public String opportunityId;
        @InvocableVariable(label='Opportunity Sub-Type')
        public String oppSubType;
        @InvocableVariable(label='Date for asset modification')
        public Datetime requestDate;
        @InvocableVariable(label='Asset Account Ids' description='Additional accounts to be included in scope of modification.')
        public List<String> assetAccountIds;
        @InvocableVariable(label='Disable Quote Calculation' description='Disable calculation of the quote. If enabled, quote will not be calculated until subsequent changes are made seperate from this action.')
        public boolean disableCalculation;
        @InvocableVariable(label='Auto-close Renewal Types')
        public boolean autoClose;
    }   

    public class InvocableResult {
        @InvocableVariable(label='Target quote id')
        public Id quoteId;
    }

    @InvocableMethod(label='Create Asset Transaction' description='Create asset-backed quote lines on a new or existing quote.' category='Asset Management')
    public static List<InvocableResult> InvocableModifyAsset(List<InvocableParameter> parameters) {
        List<InvocableResult> results = new List<InvocableResult>();
        for (InvocableParameter p : parameters) {
            InvocableResult result = new InvocableResult();
            Id oppOrQuoteId;
            if(p.autoClose != null){
                Thrill.autoClose = p.autoClose;
            }
            if(p.disableCalculation != null) {
                Thrill.disableCalculation = p.disableCalculation;
            }
            if(p.quoteId != null && p.quoteId != '') {
                oppOrQuoteId = p.quoteId;
            } else if (p.opportunityId != null && p.opportunityId != '') {
                oppOrQuoteId = p.opportunityId;
            }
            result.quoteId = Thrill.GenerateAndSave(p.assetId, p.requestDate, Thrill.TransactionType.valueOf(p.type.toLowerCase().capitalize()), p.assetAccountIds, oppOrQuoteId, p.oppSubType);
            results.add(result);
        }
        return results;
    }
}