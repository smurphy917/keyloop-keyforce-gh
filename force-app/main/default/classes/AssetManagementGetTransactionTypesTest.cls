@isTest
public with sharing class AssetManagementGetTransactionTypesTest {
    @isTest
    public static void test() {
        List<AssetManagementActionGetTransactionTypes.TransactionTypeResult> results = AssetManagementActionGetTransactionTypes.GetTransactionTypes();
        AssetManagementActionGetTransactionTypes.TransactionTypeResult result = results[0];
        System.assert(result.types.size() == 2 || result.types.size() == 3);
    }
}