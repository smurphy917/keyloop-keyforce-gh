public class AssetManagementActionRecalculateAsset {
    @TestVisible
    public class InvocableParameter {
        @InvocableVariable(label='Updated Asset')
        public Asset asset;
        @InvocableVariable(label='Run asynchronously')
        public Boolean async;
        @InvocableVariable(label='Named Credential for internal REST calls')
        public String namedCredential;
    }   

    public class InvocableResult {
        @InvocableVariable(label='Updated Asset')
        public Asset asset;
    }

    @InvocableMethod(label='Recalculate Asset' description='Recalculate asset details based on child assets and ' category='Asset Management')
    public static List<InvocableResult> InvocableRecalculateAsset(List<InvocableParameter> parameters) {
        List<InvocableResult> results = new List<InvocableResult>();
        for (InvocableParameter p : parameters) {
            InvocableResult result = new InvocableResult();
            if(p.asset != null) {
                if(p.async == true) {
                    FutureRecalculateAsset((String) p.asset.Id, p.namedCredential);
                } else {
                    AssetManagement.RecalculateAsset(p.asset, p.namedCredential);
                    result.asset = p.asset;
                }
            } else {
                // TODO: handle other create/update from contexts.
                throw new InvalidParameterException('Asset must be provided');
            }
            results.add(result);
        }
        return results;
    }

    @Future(callout=true)
    public static void FutureRecalculateAsset(String assetId, String namedCredential) {
        Asset a = [SELECT Id, RootAssetId, ParentId FROM Asset WHERE Id = :assetId];
        AssetManagement.RecalculateAsset(a, namedCredential);
    }

    public class InvalidParameterException extends Exception {

    }
}