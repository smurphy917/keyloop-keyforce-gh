public with sharing class AssetManagementActionGetTransactionTypes {
    public class TransactionTypeRequest {

    }

    public class TransactionTypeResult {
        @InvocableVariable(label='Result')
        public List<AssetManagementTransactionType> types;
    }

    @InvocableMethod(label='Get Available Transaction Types')
    public static List<TransactionTypeResult> GetTransactionTypes() {
        TransactionTypeResult result = new TransactionTypeResult();
        AssetManagementTransactionType amendment = new AssetManagementTransactionType();
        amendment.label = 'Amendment';
        amendment.value = Thrill.TransactionType.Amendment.name();
        AssetManagementTransactionType recontract = new AssetManagementTransactionType();
        recontract.label = 'Re-Contract';
        recontract.value = Thrill.TransactionType.Recontract.name();
        result.types = new List<AssetManagementTransactionType>{
            amendment,
            recontract
        };
        if(FeatureManagement.checkPermission('Manually_Generate_Renewal')) {
            AssetManagementTransactionType renewal = new AssetManagementTransactionType();
            renewal.label = 'Renewal';
            renewal.value = Thrill.TransactionType.Renewal.name();
            result.types.add(renewal);
        }
        return new List<TransactionTypeResult>{result};
    }
}