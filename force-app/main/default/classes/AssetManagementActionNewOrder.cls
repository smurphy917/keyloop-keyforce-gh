public class AssetManagementActionNewOrder {
    @TestVisible
    public class InvocableParameter {
        @InvocableVariable(label='Order Id' required=true)
        public Id orderId;
        @InvocableVariable(label='Named Credential' description='Key of a Named Credential to be used for internal REST calls')
        public String namedCredential;
    }   
    @TestVisible
    public class InvocableResult {
        @InvocableVariable(label='Job Id' description='Id for the AsyncApexJob created')
        public Id jobId;
    }

    @InvocableMethod(label='Create/Update Order Assets' description='Create new, or update existing, assets based on the provided order and context.' category='Asset Management')
    public static List<InvocableResult> InvocableGenerateAssets(List<InvocableParameter> parameters) {
        List<InvocableResult> results = new List<InvocableResult>();
        for (InvocableParameter p : parameters) {
            InvocableResult result = new InvocableResult();
            Serenity.namedCredential = p.namedCredential;
            result.jobId = Serenity.AsyncRequest(Serenity.AsyncAction.Order, p.orderId, null); // Serenity.Order(p.orderId);
            results.add(result);
        }
        return results;
    }
}