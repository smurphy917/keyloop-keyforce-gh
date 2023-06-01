@isTest
public with sharing class AssetManagementActionOrderUpdateTest {
    @TestSetup
    static void makeData(){
        Map<String,Map<String,Object>> overrides = new Map<String,Map<String,Object>>();
        Map<String,Object> accOverrides = new Map<String,Object>();
        accOverrides.put('Blocked__c', '');
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
                SBQQ__QuoteLine__r=new SBQQ__QuoteLine__c(InternalId__c=asp.Asset.Id),
                SBQQ__Status__c = 'Completed',
                Completion_Override__c = true,
                Start_Date__c = modifyDate.date().addDays(4),
                End_Date__c = a.LifecycleEndDate.date().addDays(4),
                Date_Source__c = 'Go-Live Date'
            );
            ois.add(oi);
        }
        insert qls;
        insert ois;
        for (OrderItem oi : ois) {
            oi.SBQQ__Status__c = 'Completed';
            oi.Completion_Override__c = true;
            oi.Start_Date__c = modifyDate.date().addDays(-4);
            oi.End_Date__c = a.LifecycleEndDate.date().addDays(-4);
            oi.Date_Source__c = 'Go-Live Date';
        }
        update ois;
    }

    @isTest(seeAllData=false)
    public static void test() {
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        AssetManagementProcessTask.skipDML = true;
        AssetManagementActionOrderUpdate.InvocableParameter param = new AssetManagementActionOrderUpdate.InvocableParameter();
        Order o = [SELECT Id FROM Order LIMIT 1];
        param.orderId = o.Id;
        // Adding this line to trigger test execution on deployment vvv
        Serenity.namedCredential = 'Salesforce';
        Test.startTest();
        AssetManagementActionOrderUpdate.InvocableUpdateOrder(new List<AssetManagementActionOrderUpdate.InvocableParameter>{param});
        Test.enqueueBatchJobs(1);
        Test.stopTest();
    }
}