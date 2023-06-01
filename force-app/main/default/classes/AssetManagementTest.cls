@isTest()
public class AssetManagementTest {

    @testSetup
    static void createOrder() {

        // ProductUtility.setBypassTriggers(true);
        // Billing_Automation_v2_0_TriggerHandler.setBypassTriggers(true);

        List<SObject> objs = new List<SObject>();

        /*
        blng__BillingRule__c bRule = new blng__BillingRule__c(
            Name = 'Apex Test: Base Rule',
            blng__GenerateInvoices__c = 'Yes',
            blng__InitialBillingTrigger__c = 'Order Product Activation Date'
        );
        insert bRule;
        blng__RevenueRecognitionRule__c rRule = new blng__RevenueRecognitionRule__c(
            Name = 'Apex Test: Base Rule',
            blng__CreateRevenueSchedule__c = 'No'
        );
        insert rRule;
        blng__TaxRule__c tRule = new blng__TaxRule__c(
            Name = 'Apex Test: Base Rule'
        );
        insert tRule;
        */
        // retrieve standard PB
        // Pricebook2 stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true]; //new Pricebook2(Name='ApexTest Price Book');

        // create bundle and 2 child items
        Product2 bundleRoot = new Product2(
            Name = 'Apex Test: Bundle Root'
            // blng__BillingRule__c = bRule.Id,
            // blng__RevenueRecognitionRule__c = rRule.Id,
            // blng__TaxRule__c = tRule.Id
        );
        Product2 childItem1 = new Product2(
            Name = 'Apex Test: Child Item 1'
            // blng__BillingRule__c = bRule.Id,
            // blng__RevenueRecognitionRule__c = rRule.Id,
            // blng__TaxRule__c = tRule.Id
        );
        Product2 childItem2 = new Product2(
            Name = 'Apex Test: Child Item 2'
            // blng__BillingRule__c = bRule.Id,
            // blng__RevenueRecognitionRule__c = rRule.Id,
            // blng__TaxRule__c = tRule.Id
        );
        Product2[] prods = new Product2[]{bundleRoot, childItem1, childItem2};
        // objs.add(bundleRoot);
        // objs.add(childItem1);
        // objs.add(childItem2);
        // objs.add(stdPb);
        //insert stdPb;
        insert prods;
        // create standard prices for all items
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        for (Product2 prod : prods) {
            PricebookEntry pbe = new PricebookEntry(
                Product2Id = prod.Id,
                Pricebook2Id = Test.getStandardPricebookId(),
                UnitPrice = 1
            );
            pbes.add(pbe);
            // objs.add(pbe);
        }
        insert pbes;
        // create account
        Account a = new Account(
            Name='Apex Test Account'
        );
        insert a;
        //objs.add(a);
        // create order
        Order o = new Order(
            AccountId = a.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            EffectiveDate = Date.today(),
            Status = 'Draft'
            // blng__BillingDayOfMonth__c = '1'
        );
        // objs.add(o);
        insert o;
        List<OrderItem> ois = new List<OrderItem>();
        // create root OrderItem
        OrderItem rootOi = new OrderItem(
            OrderId = o.Id,
            Product2Id = bundleRoot.Id,
            SBQQ__ChargeType__c = 'One-Time',
            PricebookEntryId = pbes[0].Id,
            UnitPrice = 100,
            Quantity = 1,
            ServiceDate = Date.today()
        );
        insert rootOi;
        // objs.add(rootOi);
        OrderItem oi_1 = new OrderItem(
            OrderId = o.Id,
            Product2Id = childItem1.Id,
            SBQQ__RequiredBy__c = rootOi.Id, // subscription
            SBQQ__BundleRoot__c = rootOi.Id,
            SBQQ__ChargeType__c = 'Recurring',
            SBQQ__BillingType__c = 'Advance',
            SBQQ__BillingFrequency__c = 'Monthly',
            PricebookEntryId = pbes[1].Id,
            UnitPrice = 40,
            Quantity = 1,
            ServiceDate = Date.today()
        );
        // objs.add(oi_1);
        OrderItem oi_2 = new OrderItem(
            OrderId = o.Id,
            Product2Id = childItem2.Id,
            SBQQ__RequiredBy__c = rootOi.Id, // one-time
            SBQQ__BundleRoot__c = rootOi.Id,
            SBQQ__ChargeType__c = 'One-Time',
            PricebookEntryId = pbes[2].Id,
            UnitPrice = 60,
            Quantity = 1,
            ServiceDate = Date.today()
        );
        // objs.add(oi_2);

        
        // Database.insert(objs);
        
        // insert new Product2[]{bundleRoot, childItem1, childItem2};
        // insert stdPb;
        // insert pbes;
        // insert a;
        // insert o;
        insert new OrderItem[]{oi_1, oi_2};
    }
    @isTest ()
    static void createTest () {
        Test.setMock(HttpCalloutMock.class, new TranquilityMock());
        Order o = [SELECT Id FROM Order WHERE Account.Name='Apex Test Account' LIMIT 1];
        System.assertNotEquals(o, null);
        AssetManagementActionGenerateAll.InvocableParameter params = new AssetManagementActionGenerateAll.InvocableParameter();
        params.orderId = o.Id;
        params.namedCredential = 'Salesforce';
        params.async = false;
        List<AssetManagementActionGenerateAll.InvocableParameter> pList = new List<AssetManagementActionGenerateAll.InvocableParameter>();
        pList.add(params);
        Test.startTest();
        AssetManagementActionGenerateAll.InvocableGenerateAssets(pList);
        Test.stopTest();
        List<OrderItem> ois = [SELECT Id, SBQQ__RequiredBy__c, Asset__c FROM OrderItem WHERE OrderId = :o.Id];
        for (OrderItem oi : ois) {
            // AssetActionSource aas = [SELECT Id, AssetAction.AssetId, AssetAction.Asset.ParentId FROM AssetActionSource WHERE ReferenceEntityItemId = :oi.Id];
            // System.assertNotEquals(aas, null);
            // System.assertEquals(aas.AssetAction.AssetId, oi.Asset__c);
            if(oi.SBQQ__RequiredBy__c != null) {
                // System.assertNotEquals(aas.AssetAction.Asset.ParentId, null);
            }
        }
    }
}