public with sharing class ConfigurationValueMap {
    @AuraEnabled
    public static getValue(String key){
        try {
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    public ConfigurationValueMap() {
        
    }
}