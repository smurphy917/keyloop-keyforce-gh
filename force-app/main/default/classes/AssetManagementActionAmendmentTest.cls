@isTest
public with sharing class AssetManagementActionAmendmentTest {
    @TestSetup
    static void makeData(){
        Map<String, Map<String,Object>> overrides = new Map<String, Map<String,Object>>();
        Map<String,Object> accOverrides = new Map<String,Object>();
        accOverrides.put('Blocked__c','');
        overrides.put('Account',accOverrides);
        String[] objs = new String[]{
            'Pricebook2',
            'Product2',
            'PricebookEntry',
            'Legal_Entity__c',
            'Account',
            'Asset',
            'AssetStatePeriod'
            // 'CustomNotificationType'
        };
        List<SObject> records = TestUtility.loadData('testDataAssetManagement', objs, overrides);
        createOrder();
    }
    
    static void createOrder (){
        // Retrieve root asset from TestSetup method
        Asset a = [SELECT Id, AccountId, LifecycleStartDate, LifecycleEndDate FROM Asset WHERE HasLifecycleManagement = true AND ParentId = null AND Aggregate_Asset__c = null LIMIT 1];
        Asset subAsset = [SELECT Id, AccountId, Product2Id, LifecycleEndDate FROM Asset WHERE Aggregate_Asset__c = :a.Id];
        // Set modify date as midpoint of lifecycle
        Datetime modifyDate = Datetime.valueOf((a.LifecycleStartDate.getTime() + a.LifecycleEndDate.getTime()) / 2);
        System.debug('MODIFY DATE: ' + modifyDate);
        // Retrieve descendant assets as ASPs
        List<AssetStatePeriod> descASPs = [SELECT Id, Asset.Product2Id, Asset.ParentId, Quantity, EndDate FROM AssetStatePeriod WHERE Asset.RootAssetId = :subAsset.Id AND StartDate <= :modifyDate AND EndDate >= :modifyDate ];
        // Build list of product2 ids
        List<String> pIds = new List<String>();
        for (AssetStatePeriod asp : descASPs) {
            pIds.add(asp.Asset.Product2Id);
        }
        // Retrieve Pricebook2 from TestSetup
        Pricebook2 pb = [SELECT Id FROM Pricebook2];
        // Get pricebook entries from TestSetup
        List<PricebookEntry> pbes = [SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :pb.Id AND Product2Id IN :pIds];
        // Bulid map of product2 ids to PBE ids
        Map<Id,Id> pIdToPBEId = new Map<Id,Id>();
        for (PricebookEntry pbe : pbes) {
            pIdToPBEId.put(pbe.Product2Id, pbe.Id);
        }
        Opportunity opp = new Opportunity(
            StageName='Qualification',
            Name='TEST',
            AccountId=a.AccountId,
            CloseDate=Date.today().addMonths(1),
            Pricebook2Id=pb.Id
        );
        insert opp;
        SBQQ__Quote__c q = new SBQQ__Quote__c(
            SBQQ__Account__c=a.AccountId,
            SBQQ__Pricebook__c=pb.Id,
            SBQQ__PricebookId__c=pb.Id,
            SBQQ__Type__c='Amendment',
            SBQQ__Opportunity2__c = opp.Id,
            SBQQ__Primary__c=true,
            SBQQ__Status__c='Closed'
        );
        insert q;
        q.SBQQ__Status__c='Closed';
        update q;
        // Create amendment order to test amendment flow
        Order o = new Order(
            AccountId=a.AccountId,
            Pricebook2Id=pb.Id,
            Status='Draft',
            EffectiveDate=modifyDate.date(),
            SBQQ__Quote__c=q.Id
        );
        insert o;
        // Add order items for each descendant asset
        List<SBQQ__QuoteLine__c> qls = new List<SBQQ__QuoteLine__c>();
        List<OrderItem> ois = new List<OrderItem>();
        Boolean first = true;
        SBQQ__QuoteLine__c rootQl = new SBQQ__QuoteLine__c(
            Asset__c=subAsset.Id,
            SBQQ__Quote__c=q.Id,
            SBQQ__Product__c=subAsset.Product2Id,
            SBQQ__Quantity__c=1,
            SBQQ__PriorQuantity__c=1,
            InternalId__c=subAsset.Id,
            SBQQ__StartDate__c=modifyDate.date(),
            SBQQ__EndDate__c=subAsset.LifecycleEndDate.date(),
            SBQQ__Incomplete__c=true,
            SBQQ__Existing__c=true
        );
        insert rootQl;
        for (AssetStatePeriod asp : descASPs) {
            if(asp.Asset.Id == subAsset.Id) {
                continue;
            }
            SBQQ__QuoteLine__c ql = new SBQQ__QuoteLine__c(
                Asset__c=asp.Asset.Id,
                SBQQ__Quote__c=q.Id,
                SBQQ__Product__c=asp.Asset.Product2Id,
                SBQQ__Quantity__c=asp.Quantity + 1,
                SBQQ__PriorQuantity__c=asp.Quantity,
                InternalId__c=asp.Asset.Id,
                SBQQ__StartDate__c=modifyDate.date(),
                SBQQ__EndDate__c=asp.EndDate.date(),
                SBQQ__Incomplete__c=true,
                SBQQ__Existing__c=true,
                BundleRoot__c=rootQl.Id,
                SBQQ__RequiredBy__c=rootQl.Id
            );
            qls.add(ql);
            OrderItem oi = new OrderItem(
                OrderId=o.Id,
                PricebookEntryId=pIdToPBEId.get(asp.Asset.Product2Id),
                Product2Id=asp.Asset.Product2Id,
                Asset__c=asp.Asset.Id,
                Modified_Root_Asset__c = subAsset.Id,
                Quantity=1, // adding 1 quantity to each
                UnitPrice=10,
                ServiceDate=modifyDate.date(),
                EndDate=a.LifecycleEndDate.date(),
                SBQQ__QuoteLine__r=new SBQQ__QuoteLine__c(InternalId__c=asp.Asset.Id)
            );
            ois.add(oi);
        }
        insert qls;
        insert ois;
        for (OrderItem oi : ois) {
            System.assertNotEquals(0, oi.TotalPrice);
        }
    }
    
    @isTest
    static void testAmendment() {
        AssetManagementProcessTask.skipDML = true;
        Order o = [SELECT Id FROM Order LIMIT 1];
        AggregateResult res = [SELECT Count(Id) linesCount FROM OrderItem WHERE OrderId = :o.Id];
        System.assertNotEquals(0, (Integer) res.get('linesCount'));
        System.debug(JSON.serialize([SELECT Id, TotalPrice FROM OrderItem WHERE OrderId = :o.Id]));
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        AssetManagementActionNewOrder.InvocableParameter param = new AssetManagementActionNewOrder.InvocableParameter();
        param.orderId = o.Id;
        param.namedCredential = 'Salesforce';
        Test.startTest();
        List<AssetManagementActionNewOrder.InvocableResult> results = AssetManagementActionNewOrder.InvocableGenerateAssets(new AssetManagementActionNewOrder.InvocableParameter[]{param});
        System.debug('TASKS: ' + JSON.serialize(Serenity.queue));
        Test.stopTest();
        Integer touched = 0;
        for (StagedRecord rec : StagedDatabase.all()) {
            if(rec.getType() == 'Asset' && rec.stagedFor != StagedRecord.StagedAction.NoAction) {
                touched++;
            }
        }
        // for (AssetManagementActionNewOrder.InvocableResult result : results) {
        System.assertEquals(((Integer)res.get('linesCount') + 1) * 2, touched);
        // }
    }
    @isTest
    static void testAmendmentBatch() {
        AssetManagementProcessTask.skipDML = true;
        Order o = [SELECT Id FROM Order LIMIT 1];
        AggregateResult res = [SELECT Count(Id) linesCount FROM OrderItem WHERE OrderId = :o.Id];
        System.debug('ASSETS: ' + JSON.serialize([SELECT Id, (SELECT Id, StartDate, EndDate FROM AssetStatePeriods) FROM Asset]));
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        AssetManagementActionNewOrder.InvocableParameter param = new AssetManagementActionNewOrder.InvocableParameter();
        param.orderId = o.Id;
        param.namedCredential = 'Salesforce';
        Test.startTest();
        List<AssetManagementActionNewOrder.InvocableResult> results = AssetManagementActionNewOrder.InvocableGenerateAssets(new AssetManagementActionNewOrder.InvocableParameter[]{param});
        // System.debug('QUEUE: \n' + JSON.serialize(AssetManagement.getQueue()));
        Database.executeBatch(new BatchableProcessAssetManagementTasks(Serenity.queue, StagedDatabase.getState(), o.Id, 'Order Activation', null), Serenity.queue.size());
        Test.stopTest();
        Integer touched = 0;
        for (StagedRecord rec : StagedDatabase.all()) {
            if(rec.getType() == 'Asset' && rec.stagedFor != StagedRecord.StagedAction.NoAction) {
                touched++;
            }
        }
        // for (AssetManagementActionNewOrder.InvocableResult result : results) {
        System.assertEquals(((Integer)res.get('linesCount') + 1) * 2, touched);
        // }
    }
    @isTest
    static void testAmendmentBatchRequestLimit() {
        AssetManagementProcessTask.skipDML = true;
        Order o = [SELECT Id FROM Order LIMIT 1];
        AggregateResult res = [SELECT Count(Id) linesCount FROM OrderItem WHERE OrderId = :o.Id];
        Test.setMock(HttpCalloutMock.class, new TranquilityMock(true));
        AssetManagementActionNewOrder.InvocableParameter param = new AssetManagementActionNewOrder.InvocableParameter();
        param.orderId = o.Id;
        param.namedCredential = 'Salesforce';
        Test.startTest();
        List<AssetManagementActionNewOrder.InvocableResult> results = AssetManagementActionNewOrder.InvocableGenerateAssets(new AssetManagementActionNewOrder.InvocableParameter[]{param});
        // System.debug('QUEUE: \n' + JSON.serialize(AssetManagement.getQueue()));
        // Database.executeBatch(new BatchableProcessAssetManagementTasks(Serenity.queue, StagedDatabase.getState(), o.Id, 'Order Activation', null), Serenity.queue.size());
        Test.stopTest();
        Integer touched = 0;
        for (StagedRecord rec : StagedDatabase.all()) {
            if(rec.getType() == 'Asset' && rec.stagedFor != StagedRecord.StagedAction.NoAction) {
                touched++;
            }
        }
        // for (AssetManagementActionNewOrder.InvocableResult result : results) {
        System.assertEquals(((Integer)res.get('linesCount') + 1) * 2, touched);
        // }
    }
}