public with sharing class SearchExecutorController {
    public Product2[] products {get; set;}
    public String error {get; set;}
    public SearchExecutorController() {
        this.products = [SELECT Id FROM Product2 WHERE IsActive = true AND SBQQ__Component__c = false AND ParentProduct__c = null];
    }
}