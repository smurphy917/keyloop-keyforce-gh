public with sharing class ConfigurationInputsController {
    public class SBProduct {
        @AuraEnabled
        public Map<String,Object> configurationAttributes;
        @AuraEnabled
        public String configuredProductId;
    }

    @AuraEnabled
    public static string getConfigFlow(SBProduct input){
        try {
            Product2 prod = [SELECT Id, Configuration_Flow__c FROM Product2 WHERE Id = :input.configuredProductId];
            return prod.Configuration_Flow__c;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}