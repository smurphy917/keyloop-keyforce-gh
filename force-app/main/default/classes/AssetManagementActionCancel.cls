public class AssetManagementActionCancel {
    @TestVisible
    public class InvocableParameter {
        @InvocableVariable(label='Id of Account to remove assets from.')
        public String accountId;
        @InvocableVariable(label='Asset id to cancel')
        public String assetId;
        @InvocableVariable(label='Cancel all descendants?')
        public Boolean includeDescendants = false;
        @InvocableVariable(label='Named Credential to be used for internal REST calls.')
        public String namedCredential;
    }
    public class InvocableResult {
        @InvocableVariable(label='Job Id')
        public Id jobId;
    }

    @InvocableMethod(label='Delete All Assets from Account' description='Cancel and remove all assets currently tied to the account.' category='Asset Management')
    public static List<InvocableResult> InvocableDeleteAllAssetsForAccount(List<InvocableParameter> parameters) {
        List<InvocableResult> results = new List<InvocableResult>();
        for (InvocableParameter p : parameters) {
            InvocableResult result = new InvocableResult();
            Serenity.namedCredential = p.namedCredential;
            if(p.accountId != null && p.accountId != '') {
                // Serenity.CancelAll(p.accountId);
                result.jobId = Serenity.AsyncRequest(Serenity.AsyncAction.CancelAll, p.accountId, null);
            } else if(p.assetId != null && p.assetId != '') {
                if(p.includeDescendants) {
                    // Serenity.CancelTree(p.assetId);
                    result.jobId = Serenity.AsyncRequest(Serenity.AsyncAction.CancelTree, p.assetId, null);
                } else {
                    // Serenity.CancelOne(p.assetId);
                    result.jobId = Serenity.AsyncRequest(Serenity.AsyncAction.CancelOne, p.assetId, null);
                }
            } else {
                throw new AssetManagementActionCancelException('One of account id or asset id is required.');
            }
            results.add(result);
        }
        return results;
    }

    private class AssetManagementActionCancelException extends Exception{}
}