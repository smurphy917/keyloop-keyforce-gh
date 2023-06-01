public with sharing class FlowResources {
    @AuraEnabled
    public List<String> getTransactionTypes(){
        Return new String[]{
            'Amendment',
            'Re-Contract'
        };
    }
}