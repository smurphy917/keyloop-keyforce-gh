@isTest
public with sharing class SerenityTest {
    @TestSetup
    static void makeData(){
        Map<String,Map<String,Object>> overrides = new Map<String,Map<String,Object>>();
        Map<String,Object> orderOverrides = new Map<String,Object>();
        orderOverrides.put('EffectiveDate', Date.today());
        overrides.put('Order', orderOverrides);
        Map<String,Object> orderItemOverrides = new Map<String,Object>();
        orderItemOverrides.put('ServiceDate', Date.today());
        overrides.put('OrderItem', orderItemOverrides);
        Map<String,Object> acc01Overrides = new Map<String,Object>();
        acc01Overrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Company').getRecordTypeId());
        acc01Overrides.put('Blocked__c','');
        Map<String,Object> acc02Overrides = new Map<String,Object>();
        acc02Overrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Dealer').getRecordTypeId());
        acc02Overrides.put('Blocked__c','');
        overrides.put('testDataAssetManagementAccount01', acc01Overrides);
        overrides.put('testDataAssetManagementAccount02', acc02Overrides);
        TestUtility.loadData(
            'testDataAssetManagement',
            new String[]{
                'Pricebook2',
                'Product2',
                'PricebookEntry',
                'Legal_Entity__c',
                'Account',
                'Opportunity',
                'SBQQ__Quote__c',
                'Order',
                'OrderItem',
                'Asset',
                'AssetStatePeriod'
                //'CustomNotificationType'
            },
            overrides
        );
    }
    @isTest
    public static void OrderTest() {
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        AssetManagementProcessTask.skipDML = true;
        Order o = [SELECT Id FROM Order LIMIT 1];
        Test.startTest();
        Serenity.Order(o.Id);
        Test.stopTest();
    }
    @isTest
    public static void BaseTest() {
        // StagedAssetStatePeriod asp = new StagedAssetStatePeriod();
        // asp.StartDate = Datetime.now();
        // asp.EndDate = Datetime.now().addDays(12);
        // asp.Quantity = 2.0;
        // asp.Amount = 400.0;
        // asp.Mrr = 89.50;
        // System.debug(asp.toJSON());
        List<Product2> ps = [SELECT Id FROM Product2];
        Account acc = [SELECT Id FROM Account LIMIT 1];

        StagedAsset a1 = new StagedAsset(new Asset(
            Product2Id = ps[0].Id,
            AccountId = acc.Id
        ));
        StagedAssetAction aa = new StagedAssetAction(new AssetAction(
            CategoryEnum='Initial Sale',
            QuantityChange=2,
            Amount=100,
            ActionDate=Datetime.now()
        ));
        aa.AssetActionSources.add(new AssetActionSource(
            ExternalReference = 'some val'
        ));
        System.debug(aa.toJSON(true));
        System.debug(aa.toAssetAction());
    }
    @isTest
    public static void QueueableAssetManagementProcessTaskTest() {
        Legal_Entity__c ent = new Legal_Entity__c(
            Name = 'Test Legal Entity'
        );
        insert ent;
        System.enqueueJob(
            new QueueableAssetManagementProcessTask(
                new AssetManagementProcessTask(
                    PWUtils.DMLOperation.DML_INSERT,
                    new Account(
                        Name = 'QAMPT Test Account',
                        Type = 'Standard',
                        Legal_Entity__c = ent.Id
                    )
                )
            )
        );
    }
    @isTest
    public static void AsyncOrderTest() {
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        AssetManagementProcessTask.skipDML = true;
        Order o = [SELECT Id FROM Order LIMIT 1];
        Test.startTest();
        // System.enqueueJob(new Serenity.AsyncHandler(Serenity.AsyncAction.Order,o.Id,null));
        Serenity.AsyncRequest(Serenity.AsyncAction.Order,o.Id,null);
        Test.stopTest();
    }

    @isTest
    public static void AsyncEndDateTest() {
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        AssetManagementProcessTask.skipDML = true;
        AssetStatePeriod asp = [SELECT AssetId, StartDate, EndDate FROM AssetStatePeriod WHERE Mrr > 0 LIMIT 1];
        System.debug(JSON.serialize(asp));
        Test.startTest();
        // System.enqueueJob(new Serenity.AsyncHandler(Serenity.AsyncAction.EndDate,asp.AssetId,asp.StartDate.date().addDays(asp.StartDate.date().daysBetween(asp.EndDate.date()) / 2)));
        Serenity.AsyncRequest(Serenity.AsyncAction.EndDate, asp.AssetId, asp.StartDate.date().addDays(asp.StartDate.date().daysBetween(asp.EndDate.date()) / 2));
        Test.stopTest();
    }
    @isTest
    public static void dmlErrorTest() {
        Order o = new Order();
        try {
            (new AssetManagementProcessTask(PWUtils.DMLOperation.DML_UPDATE, o)).process();
        } catch (Exception e) {
            System.assertEquals('AssetManagementProcessTask.TaskException',e.getTypeName());
            System.assertEquals(1,((AssetManagementProcessTask.TaskException) e).errors.size());
        }
    }
    /*
    @isTest(seeAllData=true)
    public static void LiveTest() {
        Id orderId = '80125000002u6bTAAQ';
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        AssetManagementProcessTask.skipDML = true;
        // Order o = [SELECT Id FROM Order LIMIT 1];
        Test.startTest();
        Serenity.Order(orderId);
        Test.stopTest();
        List<Asset> assets = [SELECT
            Id, (SELECT Id FROM AssetStatePeriods)
            FROM Asset
            WHERE Id IN (
                SELECT Asset__c FROM OrderItem WHERE OrderId = :orderId
            )
        ];
        for (Asset a : assets) {
            System.assertNotEquals(1, a.AssetStatePeriods.size());
        }
    }
    */
}