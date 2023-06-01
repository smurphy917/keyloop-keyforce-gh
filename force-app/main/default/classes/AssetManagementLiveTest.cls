@isTest
public with sharing class AssetManagementLiveTest {
    @isTest(seeAllData=true)
    public static void test() {
        Id orderId = '801250000032jKdAAI';
        /*
        List<OrderItem> ois = [SELECT Id FROM OrderItem WHERE OrderId = :orderId];
        for (OrderItem oi : ois) {
            oi.Asset__c = null;
        }
        update ois; 
        */
        try {
            Order o = [SELECT Id, AccountId FROM Order WHERE Id = :orderId];
            /*
            List<Asset> assets = [SELECT Id FROM Asset WHERE AccountId = :o.AccountId OR Aggregate_Asset__r.AccountId = :o.AccountId];
            Account delAcct = [SELECT Id FROM Account WHERE Name = '[DELETED ASSETS]'];
            for (Asset asset : assets) {
                asset.AccountId = delAcct.Id;
            }
            update assets;
            */
        } catch (Exception e) {
            System.debug(e);
            return;
        }
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        AssetManagementProcessTask.skipDML = true;
        Test.startTest();
        // System.runAs([SELECT Id FROM User WHERE Username = 'boomi@keyloop.com.uat'][0]) {
        // Serenity.OrderUpdate(orderId);
            
            /*
            List<OrderItem> ois = [SELECT Id, ServiceDate, EndDate, Asset__c FROM OrderItem WHERE OrderId = :orderId AND SBQQ__RequiredBy__c != null];
            List<OrderItem> toUpdate = new List<OrderItem>();
            Integer count = 0;
            for (OrderItem oi : ois) {
                if (count < 100) {
                    System.debug('UPDATED: ' + oi.Id);
                    toUpdate.add(new OrderItem(
                        Id = oi.Id,
                        Start_Date__c = Date.newInstance(2022, 05, 26),
                        End_Date__c = Date.newInstance(2023, 05, 25),
                        Date_Source__c = 'Go-Live Date'
                    ));
                } else {
                    System.debug('NOT UPDATED: ' + oi.Id);
                }
                count++;
            }
            update toUpdate;
            */
            /*
            Integer count = 0;
            for (OrderItem oi : ois) {
                if(count < 4) {
                    oi.Start_Date__c = oi.ServiceDate.addDays(-4);
                    oi.End_Date__c = oi.EndDate.addDays(-1);
                    oi.Date_Source__c = 'Go-Live Date';
                    System.debug('***COMPLETED***: ' + oi.Asset__c);
                } else {
                    oi.Start_Date__c = oi.ServiceDate;
                    oi.End_Date__c = oi.EndDate;
                    oi.Deleted__c = true;
                    System.debug('***DELETED***: ' + oi.Asset__c);
                }
                count++;
            }
            */
            
            /*
            update new OrderItem(
                Id = '8023H000001naawQAA',
                Start_Date__c = Date.newInstance(2023,05,01),
                End_Date__c = Date.NewInstance(2026,04,30),
                Date_Source__c = 'Go-Live Date'
            );
            */
            //System.debug('BUNDLE ITEM: ' + [SELECT Id, Start_Date__c, End_Date__c FROM OrderItem WHERE OrderId = :orderId AND SBQQ__BundleRoot__c = null]);
            // Test.enqueueBatchJobs(1);
            // Serenity.OrderUpdate(orderId);
            // Serenity.runAsync = true;
            // Serenity.Order(orderId);
            /*
            List<Id> rootIds = new List<Id>();
            for (OrderItem oi : [SELECT Id, Asset__r.Aggregate_Asset__r.RootAssetId FROM OrderItem WHERE OrderId = :orderId]) {
                Id rootId = oi.Asset__r.Aggregate_Asset__r.RootAssetId;
                if(rootId != null && !rootIds.contains(rootId)) {
                    rootIds.add(rootId);
                }
            }
            for (Id rootId : rootIds) {
                System.assertNotEquals(null, rootId, 'Root Asset Id is null');
                Thrill.GenerateAndSave(rootId, null, null, null, null, Thrill.TransactionType.Renewal, null, null, null);
            }
            */
            // Serenity.OrderUpdate(orderId);
            // Id assetId = '02i2500000UEUrJAAX';
            // Thrill.GenerateAndSave(assetId, null, Thrill.TransactionType.Renewal, null, null, null);
            // System.debug('TASKS: ' + JSON.serialize(Serenity.queue));
        // }
        Serenity.Order(orderId);
        Test.stopTest();
        // System.debug(StagedDatabase.toJSON());
        // System.debug(JSON.serialize(Serenity.queue));
        System.debug(StagedDatabase.toJSON());
    }
}